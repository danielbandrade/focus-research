#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(httr2); library(jsonlite); library(DBI); library(RSQLite)
  library(xml2); library(digest)
})
options(timeout = 120)

args <- commandArgs(trailingOnly = TRUE)
acao <- if (length(args)) args[[1]] else "iniciar"
stopifnot(acao %in% c("iniciar", "retomar", "atualizar"))
if (acao == "retomar") stopifnot(length(args) == 2L)
if (acao == "atualizar") stopifnot(length(args) == 3L)
coleta <- if (acao == "retomar") args[[2]] else format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
pagina_tamanho <- 4000L  # 5000 linhas foram testadas no piloto estendido.
parar_apos <- as.integer(Sys.getenv("FOCUS_PARAR_APOS_PAGINAS", "0"))
stopifnot(!is.na(parar_apos), parar_apos >= 0L)
paginas_nesta_execucao <- 0L
base_api <- "https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata"
catalogo_url <- "https://dadosabertos.bcb.gov.br/api/3/action/package_show?id=expectativas-mercado"
dir_m <- file.path("dados/manifestos", coleta)
dir_b <- file.path("dados/bruto", coleta)
banco <- file.path("dados", paste0("focus-historico-", coleta, ".sqlite"))
dir.create("dados/manifestos", recursive = TRUE, showWarnings = FALSE)
dir.create("dados/bruto", recursive = TRUE, showWarnings = FALSE)
dir.create(dir_m, showWarnings = FALSE)
dir.create(dir_b, showWarnings = FALSE)

agora <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
url_odata <- function(endpoint, parametros = list()) {
  if (!length(parametros)) return(paste0(base_api, "/", endpoint))
  pares <- paste0(URLencode(names(parametros), reserved = TRUE), "=",
                  vapply(parametros, URLencode, character(1), reserved = TRUE))
  paste0(base_api, "/", endpoint, "?", paste(pares, collapse = "&"))
}
obter <- function(url) {
  resp_body_raw(req_perform(request(url) |>
    req_user_agent("focus-research-historico/1.0 (pesquisa; API publica BCB)") |>
    req_timeout(90) |> req_retry(max_tries = 5)))
}
json_atomico <- function(obj, caminho) {
  tmp <- tempfile(tmpdir = dirname(caminho))
  on.exit(unlink(tmp), add = TRUE)
  write_json(obj, tmp, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
  stopifnot(file.rename(tmp, caminho))
}
gravar_bruto <- function(bytes, caminho) {
  tmp <- tempfile(tmpdir = dirname(caminho))
  con <- gzfile(tmp, "wb")
  writeBin(bytes, con)
  close(con)
  stopifnot(file.rename(tmp, caminho))
}
ler_bruto <- function(caminho) {
  memDecompress(readBin(caminho, "raw", n = file.info(caminho)$size), type = "gzip")
}
livre_bytes <- function() {
  linhas <- system2("df", c("-Pk", "."), stdout = TRUE)
  as.numeric(strsplit(trimws(linhas[[2]]), "[[:space:]]+")[[1]][[4]]) * 1024
}
logar <- function(...) {
  linha <- paste(agora(), ..., collapse = " ")
  cat(linha, "\n")
  cat(linha, "\n", file = file.path(dir_m, "execucao.log"), append = TRUE)
}
db_val <- function(x) if (is.null(x) || !length(x) || is.na(x)) NA_character_ else x
criar_janelas <- function(inicio, fim, unidade) {
  if (unidade == "tudo") return(list(list(id = "tudo", inicio = NA_character_, fim = NA_character_)))
  inicio <- as.Date(inicio); fim <- as.Date(fim)
  if (inicio > fim) return(list())
  formato <- if (unidade == "month") "%Y-%m-01" else "%Y-01-01"
  pontos <- seq(as.Date(format(inicio, formato)), as.Date(format(fim, formato)), by = unidade)
  lapply(pontos, function(p) {
    proximo <- seq(p, by = unidade, length.out = 2)[[2]]
    list(id = if (unidade == "month") format(p, "%Y-%m") else format(p, "%Y"),
         inicio = as.character(max(p, inicio)), fim = as.character(min(proximo - 1, fim)))
  })
}

config_arquivo <- file.path(dir_m, "config.json")
inventario_arquivo <- file.path(dir_m, "inventario.json")
if (acao != "retomar") {
  stopifnot(!file.exists(config_arquivo), !file.exists(banco))
  estimativa <- 1357031310.4152  # estimativa do piloto de 29/10/2026, em bytes
  origem <- if (acao == "atualizar") normalizePath(args[[2]], mustWork = TRUE) else NULL
  desde <- if (acao == "atualizar") as.Date(args[[3]]) else NULL
  if (acao == "atualizar") stopifnot(!is.na(desde), file.exists(origem))
  exigido <- 5 * 1024^3 + 2 * estimativa + if (is.null(origem)) 0 else file.info(origem)$size
  stopifnot(livre_bytes() >= exigido)
  cat_bytes <- obter(catalogo_url)
  writeBin(cat_bytes, file.path(dir_m, "catalogo.json"))
  catalogo <- fromJSON(rawToChar(cat_bytes), simplifyVector = FALSE)$result
  historicos <- Filter(function(r) grepl("Histórico de Alterações", r$name, fixed = TRUE), catalogo$resources)
  stopifnot(length(historicos) == 1L)
  writeBin(obter(historicos[[1]]$url), file.path(dir_m, "historico_alteracoes.csv"))
  met_bytes <- obter(paste0(base_api, "/$metadata"))
  writeBin(met_bytes, file.path(dir_m, "metadata.xml"))
  schema_hash <- digest(met_bytes, algo = "sha256", serialize = FALSE)
  xml <- read_xml(met_bytes)
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
  stopifnot(length(endpoints) == 13L, !anyDuplicated(endpoints), all(endpoints %in% names(set_map)))
  inventario <- list(); janelas <- list()
  for (i in seq_along(endpoints)) {
    endpoint <- endpoints[[i]]; r <- recursos[[i]]
    campos <- tipo_map[[set_map[[endpoint]]]]
    eixo <- if (endpoint == "DatasReferencia") "DataReferencia1" else "Data"
    extremos <- lapply(c("asc", "desc"), function(dir) {
      u <- url_odata(endpoint, list("$orderby" = paste(eixo, dir), "$top" = "1", "$format" = "json"))
      fromJSON(rawToChar(obter(u)))$value[[eixo]][[1]]
    })
    primeiro <- as.Date(extremos[[1]]); ultimo <- as.Date(extremos[[2]])
    stopifnot(!is.na(primeiro), !is.na(ultimo), primeiro <= ultimo)
    chave <- names(campos)[!(tolower(names(campos)) %in% c(
      "media", "mediana", "desviopadrao", "minimo", "maximo",
      "coeficientevariacao", "numerorespondentes"))]
    inventario[[endpoint]] <- list(nome_catalogo = r$name, id_catalogo = r$id,
      descricao_catalogo = r$description, endpoint = endpoint, entidade = set_map[[endpoint]],
      campos = as.list(campos), chave = chave, eixo = eixo,
      primeira_observacao = as.character(primeiro), ultima_observacao = as.character(ultimo))
    if (endpoint == "DatasReferencia") {
      janelas[[endpoint]] <- criar_janelas(primeiro, ultimo, "tudo")
    } else {
      a <- if (is.null(desde)) primeiro else max(primeiro, desde)
      unidade <- if (endpoint %in% c("ExpectativaMercadoMensais", "ExpectativasMercadoTrimestrais",
                                   "ExpectativasMercadoAnuais", "ExpectativasMercadoTop5Mensais")) "month" else "year"
      janelas[[endpoint]] <- criar_janelas(a, ultimo, unidade)
    }
  }
  json_atomico(inventario, inventario_arquivo)
  config <- list(coleta = coleta, modo = if (is.null(origem)) "inicial" else "atualizacao",
    origem = origem, desde = if (is.null(desde)) NULL else as.character(desde),
    iniciado_utc = agora(), pagina_tamanho = pagina_tamanho, schema_sha256 = schema_hash,
    estimativa_total_bytes = estimativa, reserva_minima_bytes = 5 * 1024^3,
    janelas = janelas, catalogo_url = catalogo_url)
  json_atomico(config, config_arquivo)
} else {
  stopifnot(file.exists(config_arquivo), file.exists(inventario_arquivo))
  config <- fromJSON(config_arquivo, simplifyVector = FALSE)
  inventario <- fromJSON(inventario_arquivo, simplifyVector = FALSE)
  pagina_tamanho <- as.integer(config$pagina_tamanho)
  stopifnot(identical(config$coleta, coleta),
            digest(file = file.path(dir_m, "metadata.xml"), algo = "sha256") == config$schema_sha256)
}

precisa_iniciar <- if (!file.exists(banco)) TRUE else {
  teste <- dbConnect(SQLite(), banco)
  pronto <- "_execucao" %in% dbListTables(teste)
  dbDisconnect(teste)
  !pronto
}
if (precisa_iniciar) {
  # Antes da primeira pagina, uma inicializacao interrompida pode ser refeita.
  if (file.exists(banco)) unlink(banco)
  if (!is.null(config$origem)) stopifnot(file.copy(config$origem, banco))
  con <- dbConnect(SQLite(), banco)
  if (is.null(config$origem)) {
    for (endpoint in names(inventario)) {
      campos <- unlist(inventario[[endpoint]]$campos, use.names = TRUE)
      sql_tipos <- setNames(ifelse(campos == "Edm.Int32", "INTEGER",
                                 ifelse(campos == "Edm.Decimal", "REAL", "TEXT")), names(campos))
      dbCreateTable(con, endpoint, c(sql_tipos, recurso = "TEXT", coleta = "TEXT"))
    }
    base_contagens <- setNames(as.list(rep(0L, length(inventario))), names(inventario))
  } else {
    dbExecute(con, "DROP TABLE IF EXISTS _paginas")
    dbExecute(con, "DROP TABLE IF EXISTS _janelas")
    dbExecute(con, "DROP TABLE IF EXISTS _execucao")
    dbWithTransaction(con, {
      for (endpoint in names(inventario)) {
        esperado <- c(names(inventario[[endpoint]]$campos), "recurso", "coleta")
        stopifnot(identical(dbListFields(con, endpoint), esperado))
        if (endpoint == "DatasReferencia") {
          dbExecute(con, sprintf("DELETE FROM %s", dbQuoteIdentifier(con, endpoint)))
        } else {
          dbExecute(con, sprintf("DELETE FROM %s WHERE Data >= ?", dbQuoteIdentifier(con, endpoint)),
                    params = list(config$desde))
        }
      }
    })
    base_contagens <- lapply(names(inventario), function(e) dbGetQuery(con,
      sprintf("SELECT count(*) AS n FROM %s", dbQuoteIdentifier(con, e)))$n[[1]])
    names(base_contagens) <- names(inventario)
  }
  dbExecute(con, "CREATE TABLE _execucao (coleta TEXT PRIMARY KEY, modo TEXT, status TEXT, base_contagens TEXT, iniciado_utc TEXT, validado_utc TEXT)")
  dbExecute(con, "CREATE TABLE _paginas (coleta TEXT, recurso TEXT, janela TEXT, pagina INTEGER, arquivo TEXT, url TEXT, filtro TEXT, linhas INTEGER, bytes_json INTEGER, bytes_gzip INTEGER, sha256 TEXT, capturado_utc TEXT, data_min TEXT, data_max TEXT, indicadores_json TEXT, rowid_inicio INTEGER, rowid_fim INTEGER, PRIMARY KEY(coleta,recurso,janela,pagina))")
  dbExecute(con, "CREATE TABLE _janelas (coleta TEXT, recurso TEXT, janela TEXT, inicio TEXT, fim TEXT, status TEXT, linhas INTEGER, paginas INTEGER, concluido_utc TEXT, PRIMARY KEY(coleta,recurso,janela))")
  dbExecute(con, "INSERT INTO _execucao VALUES (?,?,?,?,?,NULL)",
            params = list(coleta, config$modo, "coletando", toJSON(base_contagens, auto_unbox = TRUE), config$iniciado_utc))
  dbDisconnect(con)
}
con <- dbConnect(SQLite(), banco)
stopifnot(dbGetQuery(con, "SELECT count(*) AS n FROM _execucao WHERE coleta = ?", params = list(coleta))$n[[1]] == 1L)
espaco_log <- file.path(dir_m, "espaco_durante.csv")
if (!file.exists(espaco_log)) cat("utc,fase,livre_bytes,exigido_bytes,banco_bytes,bruto_confirmado_bytes\n", file = espaco_log)
bruto_confirmado <- dbGetQuery(con, "SELECT coalesce(sum(bytes_gzip),0) AS n FROM _paginas WHERE coleta = ?", params = list(coleta))$n[[1]]
checar_espaco <- function(fase) {
  livre <- livre_bytes(); db_bytes <- file.info(banco)$size
  restante <- max(0, as.numeric(config$estimativa_total_bytes) - db_bytes - bruto_confirmado)
  exigido <- as.numeric(config$reserva_minima_bytes) + 2 * restante
  cat(paste(agora(), fase, format(livre, scientific = FALSE), format(exigido, scientific = FALSE),
            format(db_bytes, scientific = FALSE), format(bruto_confirmado, scientific = FALSE), sep = ","),
      "\n", file = espaco_log, append = TRUE)
  if (livre < exigido) stop(sprintf("Espaco insuficiente: livre %.2f GiB; exigido %.2f GiB", livre / 1024^3, exigido / 1024^3))
}
checar_espaco("inicio")

manifesto_janela <- function(endpoint, janela, filtro, status) {
  p <- dbGetQuery(con, "SELECT pagina,arquivo,url,linhas,bytes_json,bytes_gzip,sha256,capturado_utc,data_min,data_max,indicadores_json FROM _paginas WHERE coleta=? AND recurso=? AND janela=? ORDER BY pagina",
                  params = list(coleta, endpoint, janela$id))
  paginas <- lapply(seq_len(nrow(p)), function(i) {
    x <- as.list(p[i, ]); x$indicadores <- fromJSON(x$indicadores_json)
    x$indicadores_json <- NULL; x
  })
  json_atomico(list(coleta = coleta, recurso = endpoint, janela = janela,
                   filtro = filtro, schema_sha256 = config$schema_sha256,
                   status = status, linhas = sum(p$linhas), paginas = paginas),
              file.path(dir_m, endpoint, paste0(janela$id, ".json")))
}
dir.create(file.path(dir_m, "falhas"), showWarnings = FALSE)
for (endpoint in names(inventario)) {
  inv <- inventario[[endpoint]]
  campos <- unlist(inv$campos, use.names = TRUE)
  eixo <- inv$eixo
  indicador_col <- if ("Indicador" %in% names(campos)) "Indicador" else "indicador"
  ordem <- paste(names(campos), collapse = ",")
  dir.create(file.path(dir_b, endpoint), showWarnings = FALSE)
  dir.create(file.path(dir_m, endpoint), showWarnings = FALSE)
  for (janela in config$janelas[[endpoint]]) {
    jid <- janela$id
    pasta <- file.path(dir_b, endpoint, jid)
    dir.create(pasta, showWarnings = FALSE)
    filtro <- if (jid == "tudo") NULL else sprintf("%s ge '%s' and %s le '%s'", eixo, janela$inicio, eixo, janela$fim)
    existente <- dbGetQuery(con, "SELECT status FROM _janelas WHERE coleta=? AND recurso=? AND janela=?",
                            params = list(coleta, endpoint, jid))
    if (nrow(existente) && existente$status[[1]] == "concluida") {
      if (!file.exists(file.path(dir_m, endpoint, paste0(jid, ".json")))) manifesto_janela(endpoint, janela, filtro, "concluida")
      next
    }
    p <- dbGetQuery(con, "SELECT pagina,arquivo,url,sha256,linhas FROM _paginas WHERE coleta=? AND recurso=? AND janela=? ORDER BY pagina",
                    params = list(coleta, endpoint, jid))
    if (nrow(p)) {
      stopifnot(identical(p$pagina, seq_len(nrow(p))))
      for (k in seq_len(nrow(p))) {
        arquivo <- file.path(pasta, p$arquivo[[k]])
        stopifnot(file.exists(arquivo), digest(file = arquivo, algo = "sha256") == p$sha256[[k]])
      }
      # Uma janela interrompida so e retomada se sua ultima pagina ainda for identica na API.
      checar_espaco("retomada")
      atual <- obter(p$url[[nrow(p)]])
      antigo <- ler_bruto(file.path(pasta, p$arquivo[[nrow(p)]]))
      if (!identical(atual, antigo)) stop(sprintf("API mudou durante a pausa: %s/%s; preservar brutos e iniciar nova coleta", endpoint, jid))
    }
    skip <- if (nrow(p)) sum(p$linhas) else 0L
    num <- nrow(p) + 1L
    if (nrow(p) && tail(p$linhas, 1) < pagina_tamanho) {
      dbExecute(con, "INSERT OR REPLACE INTO _janelas VALUES (?,?,?,?,?,?,?,?,?)",
                params = list(coleta, endpoint, jid, db_val(janela$inicio), db_val(janela$fim), "concluida", skip, nrow(p), agora()))
      manifesto_janela(endpoint, janela, filtro, "concluida")
      next
    }
    repeat {
      checar_espaco(paste(endpoint, jid, num, sep = ":"))
      params <- list("$orderby" = ordem, "$top" = as.character(pagina_tamanho),
                     "$skip" = as.character(skip), "$format" = "json")
      if (!is.null(filtro)) params <- c(list("$filter" = filtro), params)
      u <- url_odata(endpoint, params)
      arquivo <- sprintf("pagina-%04d.json.gz", num)
      caminho <- file.path(pasta, arquivo)
      bytes <- tryCatch({
        if (file.exists(caminho)) ler_bruto(caminho) else {
          resposta <- obter(u)
          gravar_bruto(resposta, caminho)
          resposta
        }
      }, error = function(e) {
        json_atomico(list(utc = agora(), endpoint = endpoint, janela = jid, pagina = num,
                          url = u, erro = conditionMessage(e)),
                     file.path(dir_m, "falhas", paste0(endpoint, "-", jid, "-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".json")))
        stop(e)
      })
      obj <- fromJSON(rawToChar(bytes), simplifyDataFrame = TRUE)
      dados <- obj$value
      n <- if (is.data.frame(dados)) nrow(dados) else if (!length(dados)) 0L else stop("value nao e tabela")
      if (n > pagina_tamanho || (n > 0 && !setequal(names(dados), names(campos)))) stop("Resposta truncada ou esquema alterado")
      if (n && !is.null(filtro) && any(dados[[eixo]] < janela$inicio | dados[[eixo]] > janela$fim)) stop("Data fora da janela")
      data_min <- if (n) min(dados[[eixo]]) else NA_character_
      data_max <- if (n) max(dados[[eixo]]) else NA_character_
      indicadores <- if (n) sort(unique(dados[[indicador_col]])) else character()
      sha <- digest(file = caminho, algo = "sha256")
      bytes_gzip <- file.info(caminho)$size
      rowid_ini <- dbGetQuery(con, sprintf("SELECT coalesce(max(rowid),0) AS n FROM %s", dbQuoteIdentifier(con, endpoint)))$n[[1]]
      dbWithTransaction(con, {
        if (n) {
          dados <- dados[names(campos)]
          dados$recurso <- endpoint; dados$coleta <- coleta
          dbAppendTable(con, endpoint, dados)
        }
        rowid_fim <- dbGetQuery(con, sprintf("SELECT coalesce(max(rowid),0) AS n FROM %s", dbQuoteIdentifier(con, endpoint)))$n[[1]]
        stopifnot(rowid_fim - rowid_ini == n)
        dbExecute(con, "INSERT INTO _paginas VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
          params = list(coleta, endpoint, jid, num, arquivo, u, db_val(filtro), n, length(bytes),
                        bytes_gzip, sha, format(file.info(caminho)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        data_min, data_max, toJSON(indicadores, auto_unbox = FALSE), rowid_ini + 1L, rowid_fim))
      })
      bruto_confirmado <- bruto_confirmado + bytes_gzip
      skip <- skip + n
      manifesto_janela(endpoint, janela, filtro, "em_andamento")
      paginas_nesta_execucao <- paginas_nesta_execucao + 1L
      if (parar_apos > 0L && paginas_nesta_execucao >= parar_apos) stop("Pausa controlada apos paginas confirmadas; use retomar")
      if (n < pagina_tamanho) {
        dbExecute(con, "INSERT OR REPLACE INTO _janelas VALUES (?,?,?,?,?,?,?,?,?)",
                  params = list(coleta, endpoint, jid, db_val(janela$inicio), db_val(janela$fim), "concluida", skip, num, agora()))
        manifesto_janela(endpoint, janela, filtro, "concluida")
        logar(endpoint, jid, "linhas", skip, "paginas", num, "livre_GiB", round(livre_bytes() / 1024^3, 2))
        break
      }
      num <- num + 1L
    }
  }
}
dbExecute(con, "UPDATE _execucao SET status='coletada' WHERE coleta=?", params = list(coleta))
dbDisconnect(con)
logar("Coleta encerrada; iniciando validacao")
resultado <- system2("Rscript", c("R/validar_historico.R", coleta))
if (resultado != 0L) stop("Validacao historica falhou; versao nao publicada")
logar("Validacao concluida; snapshot", banco)
