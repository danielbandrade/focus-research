#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(DBI)
  library(RSQLite)
  library(xml2)
  library(digest)
})

options(timeout = 120)
inicio <- as.Date(Sys.getenv("FOCUS_INICIO", "2026-10-16"))
fim <- as.Date(Sys.getenv("FOCUS_FIM", "2026-10-23"))
stopifnot(!is.na(inicio), !is.na(fim), inicio <= fim)
pagina <- as.integer(Sys.getenv("FOCUS_PAGINA", "500"))
stopifnot(!is.na(pagina), pagina >= 1L, pagina <= 1000L)
coleta <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
base <- "https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata"
catalogo_url <- "https://dadosabertos.bcb.gov.br/api/3/action/package_show?id=expectativas-mercado"
dir.create("dados/bruto", recursive = TRUE, showWarnings = FALSE)
dir.create("dados/manifestos", recursive = TRUE, showWarnings = FALSE)
dir.create("dados/temporarios", recursive = TRUE, showWarnings = FALSE)
bruto_dir <- file.path("dados/bruto", coleta)
manifesto_dir <- file.path("dados/manifestos", coleta)
dir.create(bruto_dir)
dir.create(manifesto_dir)
banco <- file.path("dados", paste0("focus-piloto-", coleta, ".sqlite"))

url_odata <- function(endpoint, parametros = list()) {
  if (!length(parametros)) return(paste0(base, "/", endpoint))
  pares <- paste0(URLencode(names(parametros), reserved = TRUE), "=",
                  vapply(parametros, URLencode, character(1), reserved = TRUE))
  paste0(base, "/", endpoint, "?", paste(pares, collapse = "&"))
}
obter <- function(url) {
  req <- request(url) |>
    req_user_agent("focus-research-piloto/1.0 (pesquisa; API publica BCB)") |>
    req_timeout(90) |>
    req_retry(max_tries = 4)
  resp_body_raw(req_perform(req))
}
gravar <- function(bytes, caminho, comprimir = FALSE) {
  con <- if (comprimir) gzfile(caminho, "wb") else file(caminho, "wb")
  on.exit(close(con))
  writeBin(bytes, con)
}
json <- function(x, caminho) {
  write_json(x, caminho, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
}
tamanho <- function(caminho) {
  arquivos <- list.files(caminho, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  if (!length(arquivos)) return(0)
  info <- file.info(arquivos)
  sum(info$size[!info$isdir], na.rm = TRUE)
}
uteis <- function(a, b) {
  d <- seq(as.Date(a), as.Date(b), by = "day")
  sum(as.POSIXlt(d)$wday %in% 1:5)
}
cat("Coleta:", coleta, "\n")
catalogo_bytes <- obter(catalogo_url)
gravar(catalogo_bytes, file.path(manifesto_dir, "catalogo.json"))
catalogo <- fromJSON(rawToChar(catalogo_bytes), simplifyVector = FALSE)$result
historicos <- Filter(function(r) grepl("Histórico de Alterações", r$name, fixed = TRUE), catalogo$resources)
stopifnot(length(historicos) == 1L)
hist_url <- historicos[[1]]$url
hist_erro <- NULL
tryCatch(gravar(obter(hist_url), file.path(manifesto_dir, "historico_alteracoes.csv")),
         error = function(e) hist_erro <<- conditionMessage(e))
metadata_bytes <- obter(paste0(base, "/$metadata"))
gravar(metadata_bytes, file.path(manifesto_dir, "metadata.xml"))
esquema_hash <- digest(metadata_bytes, algo = "sha256", serialize = FALSE)
xml <- read_xml(metadata_bytes)
tipos <- xml_find_all(xml, ".//*[local-name()='EntityType']")
tipo_map <- setNames(lapply(tipos, function(t) {
  p <- xml_find_all(t, "./*[local-name()='Property']")
  setNames(xml_attr(p, "Type"), xml_attr(p, "Name"))
}), xml_attr(tipos, "Name"))
sets <- xml_find_all(xml, ".//*[local-name()='EntitySet']")
set_map <- setNames(sub(".*\\.", "", xml_attr(sets, "EntityType")), xml_attr(sets, "Name"))
recursos <- Filter(function(r) grepl("/recursos/", r$url, fixed = TRUE) &&
                     !grepl("Desativado", r$name, fixed = TRUE), catalogo$resources)
endpoints <- vapply(recursos, function(r) sub(".*recursos/", "", r$url), character(1))
stopifnot(length(recursos) == 13L, all(endpoints %in% names(set_map)),
          !anyDuplicated(endpoints))

con <- dbConnect(SQLite(), banco)
temp_ini <- tamanho(tempdir())
temp_pico <- temp_ini
sidecar_pico <- 0
inventario <- list()
validacoes <- list()
cobertura <- list()
estimativas <- list()

for (i in seq_along(recursos)) {
  r <- recursos[[i]]
  endpoint <- endpoints[[i]]
  campos <- tipo_map[[set_map[[endpoint]]]]
  eixo <- if (endpoint == "DatasReferencia") "DataReferencia1" else "Data"
  janela_ini <- if (endpoint == "DatasReferencia") as.Date(format(inicio, "%Y-%m-01")) else inicio
  janela_fim <- fim
  filtro <- sprintf("%s ge '%s' and %s le '%s'", eixo, janela_ini, eixo, janela_fim)
  estatisticas <- c("media", "mediana", "desviopadrao", "minimo", "maximo",
                   "coeficientevariacao", "numerorespondentes")
  chave <- names(campos)[!(tolower(names(campos)) %in% estatisticas)]
  ordem <- paste(names(campos), collapse = ",")
  pasta <- file.path(bruto_dir, endpoint)
  dir.create(pasta)
  paginas <- list()
  total <- 0L
  erro <- NULL
  cat(endpoint, "... ")
  tipos_sql <- setNames(ifelse(campos == "Edm.Int32", "INTEGER",
                             ifelse(campos == "Edm.Decimal", "REAL", "TEXT")), names(campos))
  dbCreateTable(con, endpoint, c(tipos_sql, recurso = "TEXT", coleta = "TEXT"))
  skip <- 0L
  repeat {
    u <- url_odata(endpoint, list("$filter" = filtro, "$orderby" = ordem,
                                  "$top" = as.character(pagina), "$skip" = as.character(skip),
                                  "$format" = "json"))
    resposta <- tryCatch(obter(u), error = function(e) { erro <<- conditionMessage(e); NULL })
    if (is.null(resposta)) break
    objeto <- tryCatch(fromJSON(rawToChar(resposta), simplifyDataFrame = TRUE),
                       error = function(e) { erro <<- conditionMessage(e); NULL })
    if (is.null(objeto) || is.null(objeto$value)) {
      if (is.null(erro)) erro <- "Resposta sem value"
      break
    }
    dados <- objeto$value
    n <- if (is.data.frame(dados)) nrow(dados) else if (!length(dados)) 0L else NULL
    if (is.null(n)) { erro <- "value nao e tabela"; break }
    if (n > 0 && !setequal(names(dados), names(campos))) {
      erro <- paste("Divergencia de esquema:", paste(names(dados), collapse = ","))
      break
    }
    arquivo <- sprintf("pagina-%04d.json.gz", length(paginas) + 1L)
    caminho <- file.path(pasta, arquivo)
    gravar(resposta, caminho, comprimir = TRUE)
    if (n > 0) {
      dados <- dados[names(campos)]
      dados$recurso <- endpoint
      dados$coleta <- coleta
      dbWithTransaction(con, {
        dbAppendTable(con, endpoint, dados)
        sidecars <- paste0(banco, c("-journal", "-wal", "-shm"))
        sidecar_pico <- max(sidecar_pico, sum(file.info(sidecars)$size, na.rm = TRUE))
      })
    }
    paginas[[length(paginas) + 1L]] <- list(
      arquivo = arquivo, url = u, filtro = filtro, skip = skip, linhas = n,
      bytes_json = length(resposta), bytes_gzip = file.info(caminho)$size,
      sha256 = digest(file = caminho, algo = "sha256"),
      recebido_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      data_min = if (n) min(dados[[eixo]], na.rm = TRUE) else NULL,
      data_max = if (n) max(dados[[eixo]], na.rm = TRUE) else NULL)
    total <- total + n
    temp_pico <- max(temp_pico, tamanho(tempdir()))
    sidecars <- paste0(banco, c("-journal", "-wal", "-shm"))
    sidecar_pico <- max(sidecar_pico, sum(file.info(sidecars)$size, na.rm = TRUE))
    if (n < pagina) break
    skip <- skip + n
  }
  extremos <- list()
  for (direcao in c("asc", "desc")) {
    u <- url_odata(endpoint, list("$orderby" = paste(eixo, direcao), "$top" = "1", "$format" = "json"))
    valor <- tryCatch(fromJSON(rawToChar(obter(u)))$value[[eixo]][[1]],
                      error = function(e) NA_character_)
    extremos[[direcao]] <- valor
  }
  inventario[[endpoint]] <- list(
    nome_catalogo = r$name, id_catalogo = r$id, endpoint = endpoint,
    grupo = if (endpoint == "DatasReferencia") "referencia" else if (grepl("Top5", endpoint)) "top5" else "agregado",
    descricao_catalogo = r$description, tipo_entidade = set_map[[endpoint]],
    campos = as.list(campos), chave_candidata = chave, eixo = eixo,
    primeira_observacao = extremos$asc, ultima_observacao = extremos$desc)
  manifest <- list(coleta = coleta, endpoint = endpoint, esquema_sha256 = esquema_hash,
                   janela_inicio = as.character(janela_ini), janela_fim = as.character(janela_fim),
                   chave_candidata = chave, linhas = total, paginas = paginas,
                   paginas_com_erro = if (is.null(erro)) 0 else 1,
                   erro = erro)
  json(manifest, file.path(manifesto_dir, paste0(endpoint, ".json")))

  tabela <- dbQuoteIdentifier(con, endpoint)
  cotas <- paste(as.character(dbQuoteIdentifier(con, chave)), collapse = ",")
  duplicatas <- dbGetQuery(con, sprintf(
    "SELECT count(*) AS n FROM (SELECT %s FROM %s GROUP BY %s HAVING count(*) > 1)",
    cotas, tabela, cotas))$n[[1]]
  linhas_sql <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", tabela))$n[[1]]
  datas_invalidas <- dbGetQuery(con, sprintf(
    "SELECT count(*) AS n FROM %s WHERE %s IS NULL OR length(%s) != 10 OR date(%s) IS NULL",
    tabela, dbQuoteIdentifier(con, eixo), dbQuoteIdentifier(con, eixo), dbQuoteIdentifier(con, eixo)))$n[[1]]
  if ("DataReferencia2" %in% names(campos)) {
    datas_invalidas <- datas_invalidas + dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM %s WHERE DataReferencia2 IS NULL OR length(DataReferencia2) != 10 OR date(DataReferencia2) IS NULL",
      tabela))$n[[1]]
  }
  numericas <- names(campos)[campos %in% c("Edm.Decimal", "Edm.Int32")]
  ausentes <- if (length(numericas)) {
    vapply(numericas, function(campo) dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM %s WHERE %s IS NULL", tabela, dbQuoteIdentifier(con, campo)))$n[[1]], numeric(1))
  } else numeric()
  tipos_invalidos <- if (length(numericas)) {
    sum(vapply(numericas, function(campo) dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM %s WHERE %s IS NOT NULL AND typeof(%s) NOT IN ('integer','real')",
      tabela, dbQuoteIdentifier(con, campo), dbQuoteIdentifier(con, campo)))$n[[1]], numeric(1)))
  } else 0
  datas <- dbGetQuery(con, sprintf("SELECT DISTINCT %s AS data FROM %s", dbQuoteIdentifier(con, eixo), tabela))$data
  validacoes[[endpoint]] <- data.frame(
    recurso = endpoint, linhas_manifesto = total, linhas_sqlite = linhas_sql,
    paginas = length(paginas), paginas_com_erro = as.integer(!is.null(erro)),
    chave_duplicada_grupos = duplicatas, datas_invalidas = datas_invalidas,
    tipos_numericos_invalidos = tipos_invalidos,
    valores_numericos_ausentes = sum(ausentes),
    datas_distintas = length(datas),
    data_min = if (length(datas)) min(datas) else NA_character_,
    data_max = if (length(datas)) max(datas) else NA_character_)
  if (linhas_sql > 0) {
    indicador <- if ("Indicador" %in% names(campos)) "Indicador" else "indicador"
    q <- sprintf("SELECT %s AS indicador, min(%s) AS data_min, max(%s) AS data_max, count(*) AS linhas, count(DISTINCT %s) AS datas_distintas FROM %s GROUP BY %s",
                 dbQuoteIdentifier(con, indicador), dbQuoteIdentifier(con, eixo),
                 dbQuoteIdentifier(con, eixo), dbQuoteIdentifier(con, eixo), tabela,
                 dbQuoteIdentifier(con, indicador))
    cob <- dbGetQuery(con, q)
    cob$recurso <- endpoint
    cob$lacunas_dias_uteis <- mapply(function(a, b, n) max(0, uteis(a, b) - n),
                                     cob$data_min, cob$data_max, cob$datas_distintas)
    cobertura[[endpoint]] <- cob
  }
  bytes_brutos <- tamanho(pasta)
  dias_piloto <- if (endpoint == "DatasReferencia") as.numeric(janela_fim - janela_ini) + 1 else uteis(janela_ini, janela_fim)
  dias_historicos <- if (is.na(extremos$asc) || is.na(extremos$desc)) NA_real_ else
    if (endpoint == "DatasReferencia") as.numeric(as.Date(extremos$desc) - as.Date(extremos$asc)) + 1 else uteis(extremos$asc, extremos$desc)
  estimativas[[endpoint]] <- data.frame(recurso = endpoint, bytes_brutos = bytes_brutos,
                                       dias_piloto = dias_piloto, dias_historicos = dias_historicos,
                                       bytes_historicos_estimados = bytes_brutos * dias_historicos / dias_piloto)
  cat(total, "linhas;", length(paginas), "paginas", if (!is.null(erro)) paste("ERRO:", erro) else "OK", "\n")
}

dbDisconnect(con)
temp_fim <- tamanho(tempdir())
valid <- do.call(rbind, validacoes)
estim <- do.call(rbind, estimativas)
cob <- if (length(cobertura)) do.call(rbind, cobertura) else data.frame()
write.csv(valid, file.path(manifesto_dir, "validacoes.csv"), row.names = FALSE, na = "")
write.csv(estim, file.path(manifesto_dir, "estimativa_espaco.csv"), row.names = FALSE, na = "")
write.csv(cob, file.path(manifesto_dir, "cobertura.csv"), row.names = FALSE, na = "")
json(inventario, file.path(manifesto_dir, "inventario.json"))
df <- system2("df", c("-Pk", "."), stdout = TRUE)
livre_kb <- as.numeric(strsplit(trimws(df[[2]]), "[[:space:]]+")[[1]][[4]])
espaco <- list(coleta = coleta, bruto_bytes = tamanho(bruto_dir),
               sqlite_bytes = file.info(banco)$size, temporario_inicio_bytes = temp_ini,
               temporario_pico_observado_bytes = temp_pico,
               temporario_fim_bytes = temp_fim,
               sqlite_sidecar_pico_bytes = sidecar_pico,
               livre_atual_bytes = livre_kb * 1024,
               historico_bruto_estimado_bytes = sum(estim$bytes_historicos_estimados, na.rm = TRUE),
               historico_sqlite_estimado_bytes = file.info(banco)$size *
                 sum(estim$bytes_historicos_estimados, na.rm = TRUE) / max(1, tamanho(bruto_dir)),
               historico_estimativa_metodo = "Extrapolacao da taxa comprimida por dia util (estatisticas) ou dia corrido (DatasReferencia); aproximacao, sem aferir mudancas historicas de cobertura.")
espaco$historico_total_estimado_bytes <- espaco$historico_bruto_estimado_bytes + espaco$historico_sqlite_estimado_bytes
espaco$fracao_espaco_livre <- espaco$historico_total_estimado_bytes / espaco$livre_atual_bytes
json(espaco, file.path(manifesto_dir, "espaco.json"))
json(list(coleta = coleta, inicio = as.character(inicio), fim = as.character(fim),
          pagina = pagina, catalogo_url = catalogo_url, historico_url = hist_url,
          historico_erro = hist_erro, metadata_sha256 = esquema_hash,
          banco = banco, session = capture.output(sessionInfo())),
     file.path(manifesto_dir, "execucao.json"))
cat("Concluido:", sum(valid$linhas_sqlite), "linhas; bruto", espaco$bruto_bytes,
    "bytes; SQLite", espaco$sqlite_bytes, "bytes\n")
if (any(valid$paginas_com_erro > 0 | valid$linhas_manifesto != valid$linhas_sqlite |
        valid$chave_duplicada_grupos > 0 | valid$datas_invalidas > 0 |
        valid$tipos_numericos_invalidos > 0)) {
  stop("Validacao falhou; consulte validacoes.csv e os manifestos por recurso.")
}
