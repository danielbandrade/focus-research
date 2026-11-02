#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(jsonlite); library(DBI); library(RSQLite); library(digest)})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
coleta <- args[[1]]
dir_m <- file.path("dados/manifestos", coleta)
dir_b <- file.path("dados/bruto", coleta)
banco <- file.path("dados", paste0("focus-historico-", coleta, ".sqlite"))
config <- fromJSON(file.path(dir_m, "config.json"), simplifyVector = FALSE)
inventario <- fromJSON(file.path(dir_m, "inventario.json"), simplifyVector = FALSE)
stopifnot(length(inventario) == 13L, file.exists(banco),
          digest(file = file.path(dir_m, "metadata.xml"), algo = "sha256") == config$schema_sha256)
con <- dbConnect(SQLite(), banco)
stopifnot(dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]] == "ok")
base_contagens <- fromJSON(dbGetQuery(con, "SELECT base_contagens FROM _execucao WHERE coleta=?",
                                   params = list(coleta))$base_contagens[[1]])
validacoes <- list(); cobertura <- list(); ausentes <- list()
total_paginas <- 0L
for (endpoint in names(inventario)) {
  inv <- inventario[[endpoint]]
  campos <- unlist(inv$campos, use.names = TRUE)
  esperado <- c(names(campos), "recurso", "coleta")
  stopifnot(identical(dbListFields(con, endpoint), esperado))
  info <- dbGetQuery(con, sprintf("PRAGMA table_info(%s)", dbQuoteIdentifier(con, endpoint)))
  tipos <- ifelse(campos == "Edm.Int32", "INTEGER", ifelse(campos == "Edm.Decimal", "REAL", "TEXT"))
  stopifnot(identical(info$type[seq_along(campos)], unname(tipos)))
  indicador_col <- if ("Indicador" %in% names(campos)) "Indicador" else "indicador"
  paginas <- 0L; linhas_novas <- 0L; datas_manifesto <- character(); indicadores_manifesto <- character()
  for (janela in config$janelas[[endpoint]]) {
    arquivo_m <- file.path(dir_m, endpoint, paste0(janela$id, ".json"))
    stopifnot(file.exists(arquivo_m))
    m <- fromJSON(arquivo_m, simplifyVector = FALSE)
    stopifnot(m$status == "concluida", length(m$paginas) > 0,
              tail(m$paginas, 1)[[1]]$linhas < as.integer(config$pagina_tamanho))
    linhas_j <- 0L
    for (k in seq_along(m$paginas)) {
      p <- m$paginas[[k]]
      stopifnot(p$pagina == k)
      bruto <- file.path(dir_b, endpoint, janela$id, p$arquivo)
      stopifnot(file.exists(bruto), file.info(bruto)$size == p$bytes_gzip,
                digest(file = bruto, algo = "sha256") == p$sha256)
      bytes <- memDecompress(readBin(bruto, "raw", n = file.info(bruto)$size), type = "gzip")
      stopifnot(length(bytes) == p$bytes_json)
      dados <- fromJSON(rawToChar(bytes), simplifyDataFrame = TRUE)$value
      n <- if (is.data.frame(dados)) nrow(dados) else if (!length(dados)) 0L else stop("value invalido")
      stopifnot(n == p$linhas, n <= as.integer(config$pagina_tamanho))
      if (n) {
        stopifnot(setequal(names(dados), names(campos)))
        if (janela$id != "tudo") stopifnot(all(dados[[inv$eixo]] >= janela$inicio & dados[[inv$eixo]] <= janela$fim))
        datas_manifesto <- c(datas_manifesto, min(dados[[inv$eixo]]), max(dados[[inv$eixo]]))
        indicadores_manifesto <- union(indicadores_manifesto, unique(dados[[indicador_col]]))
      }
      linhas_j <- linhas_j + n
      paginas <- paginas + 1L
    }
    stopifnot(linhas_j == m$linhas)
  }
  linhas_novas <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE coleta=?", dbQuoteIdentifier(con, endpoint)),
                             params = list(coleta))$n[[1]]
  linhas_banco <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", dbQuoteIdentifier(con, endpoint)))$n[[1]]
  linhas_ledger <- dbGetQuery(con, "SELECT coalesce(sum(linhas),0) AS n FROM _paginas WHERE coleta=? AND recurso=?",
                               params = list(coleta, endpoint))$n[[1]]
  stopifnot(linhas_novas == linhas_ledger,
            linhas_banco == as.numeric(base_contagens[[endpoint]]) + linhas_novas)
  minimo_novo <- dbGetQuery(con, sprintf("SELECT min(%s) AS minimo, max(%s) AS maximo FROM %s WHERE coleta=?",
    dbQuoteIdentifier(con, inv$eixo), dbQuoteIdentifier(con, inv$eixo), dbQuoteIdentifier(con, endpoint)),
    params = list(coleta))
  if (length(datas_manifesto)) stopifnot(min(datas_manifesto) == minimo_novo$minimo[[1]],
                                         max(datas_manifesto) == minimo_novo$maximo[[1]])
  if (config$modo == "inicial") {
    sql <- sprintf("SELECT DISTINCT %s AS indicador FROM %s", dbQuoteIdentifier(con, indicador_col), dbQuoteIdentifier(con, endpoint))
    stopifnot(setequal(indicadores_manifesto, dbGetQuery(con, sql)$indicador))
  }
  chave <- unlist(inv$chave, use.names = FALSE)
  # O indice da chave acelera a checagem e as consultas; GROUP BY tambem detecta NULL duplicado.
  nome_indice <- paste0("idx_", endpoint, "_chave")
  campos_sql <- paste(as.character(dbQuoteIdentifier(con, chave)), collapse = ",")
  livre <- as.numeric(strsplit(trimws(system2("df", c("-Pk", "."), stdout = TRUE)[[2]]), "[[:space:]]+")[[1]][[4]]) * 1024
  if (livre < 5 * 1024^3 + 2 * file.info(banco)$size) stop("Espaco insuficiente para criar indices")
  dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (%s)",
                         dbQuoteIdentifier(con, nome_indice), dbQuoteIdentifier(con, endpoint), campos_sql))
  duplicatas <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM (SELECT %s FROM %s GROUP BY %s HAVING count(*) > 1)",
    campos_sql, dbQuoteIdentifier(con, endpoint), campos_sql))$n[[1]]
  # O segundo indice cobre consultas por indicador, periodo, calculo e data.
  periodo <- intersect(c("DataReferencia", "Reuniao", "reuniao", "periodo", "Suavizada"), names(campos))
  outras <- intersect(c("IndicadorDetalhe", "tipoCalculo", "baseCalculo", "Suavizada"), names(campos))
  serie <- unique(c(indicador_col, periodo, outras, inv$eixo))
  nome_serie <- paste0("idx_", endpoint, "_serie")
  dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (%s)",
    dbQuoteIdentifier(con, nome_serie), dbQuoteIdentifier(con, endpoint),
    paste(as.character(dbQuoteIdentifier(con, serie)), collapse = ",")))
  if (inv$eixo == "Data") dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (Data)",
    dbQuoteIdentifier(con, paste0("idx_", endpoint, "_data")), dbQuoteIdentifier(con, endpoint)))
  datas_col <- if (endpoint == "DatasReferencia") c("DataReferencia1", "DataReferencia2") else "Data"
  invalidas <- sum(vapply(datas_col, function(col) dbGetQuery(con, sprintf(
    "SELECT count(*) AS n FROM %s WHERE %s IS NULL OR length(%s) != 10 OR date(%s) IS NULL",
    dbQuoteIdentifier(con, endpoint), dbQuoteIdentifier(con, col), dbQuoteIdentifier(con, col), dbQuoteIdentifier(con, col)))$n[[1]], numeric(1)))
  numericas <- names(campos)[campos %in% c("Edm.Decimal", "Edm.Int32")]
  tipos_invalidos <- 0L
  for (col in numericas) {
    nulos <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s IS NULL",
      dbQuoteIdentifier(con, endpoint), dbQuoteIdentifier(con, col)))$n[[1]]
    invalidos <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s IS NOT NULL AND typeof(%s) NOT IN ('integer','real')",
      dbQuoteIdentifier(con, endpoint), dbQuoteIdentifier(con, col), dbQuoteIdentifier(con, col)))$n[[1]]
    ausentes[[length(ausentes) + 1L]] <- data.frame(recurso = endpoint, campo = col, ausentes = nulos,
                                                    tipos_invalidos = invalidos)
    tipos_invalidos <- tipos_invalidos + invalidos
  }
  sql_cob <- sprintf("SELECT %s AS indicador, min(%s) AS data_min, max(%s) AS data_max, count(*) AS linhas, count(DISTINCT %s) AS datas_distintas FROM %s GROUP BY %s",
    dbQuoteIdentifier(con, indicador_col), dbQuoteIdentifier(con, inv$eixo), dbQuoteIdentifier(con, inv$eixo),
    dbQuoteIdentifier(con, inv$eixo), dbQuoteIdentifier(con, endpoint), dbQuoteIdentifier(con, indicador_col))
  cob <- dbGetQuery(con, sql_cob)
  cob$recurso <- endpoint
  cob$eixo <- inv$eixo
  cob$ultima_extracao_utc <- dbGetQuery(con,
    "SELECT max(capturado_utc) AS data FROM _paginas WHERE coleta=? AND recurso=?",
    params = list(coleta, endpoint))$data[[1]]
  cob$lacunas_dias_uteis <- if (inv$eixo == "Data") mapply(function(a, b, n) {
    d <- seq(as.Date(a), as.Date(b), by = "day")
    max(0, sum(as.POSIXlt(d)$wday %in% 1:5) - n)
  }, cob$data_min, cob$data_max, cob$datas_distintas) else NA_integer_
  cobertura[[endpoint]] <- cob
  validacoes[[endpoint]] <- data.frame(recurso = endpoint, linhas_sqlite = linhas_banco,
    linhas_novas = linhas_novas, linhas_brutas = linhas_ledger, paginas = paginas,
    janelas = length(config$janelas[[endpoint]]), chaves_duplicadas_grupos = duplicatas,
    datas_invalidas = invalidas, tipos_numericos_invalidos = tipos_invalidos,
    indicadores = nrow(cob), data_min = min(cob$data_min), data_max = max(cob$data_max))
  total_paginas <- total_paginas + paginas
  cat(endpoint, linhas_banco, "linhas;", paginas, "paginas;", duplicatas, "chaves duplicadas\n")
}
valid <- do.call(rbind, validacoes)
write.csv(valid, file.path(dir_m, "validacoes_historicas.csv"), row.names = FALSE)
write.csv(do.call(rbind, cobertura), file.path(dir_m, "cobertura_historica.csv"), row.names = FALSE)
write.csv(do.call(rbind, ausentes), file.path(dir_m, "ausentes_historicos.csv"), row.names = FALSE)

if (config$modo == "atualizacao") {
  dbExecute(con, paste("ATTACH DATABASE", dbQuoteString(con, config$origem), "AS anterior"))
  revisoes <- lapply(names(inventario), function(endpoint) {
    campos <- names(inventario[[endpoint]]$campos)
    lista <- paste(as.character(dbQuoteIdentifier(con, campos)), collapse = ",")
    filtro <- if (endpoint == "DatasReferencia") "1=1" else
      paste0("Data >= ", as.character(dbQuoteString(con, config$desde)))
    anterior <- paste0("anterior.", as.character(dbQuoteIdentifier(con, endpoint)))
    atual <- paste0("main.", as.character(dbQuoteIdentifier(con, endpoint)))
    antes <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s", anterior, filtro))$n[[1]]
    depois <- dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s", atual, filtro))$n[[1]]
    so_antes <- dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM (SELECT %s FROM %s WHERE %s EXCEPT SELECT %s FROM %s WHERE %s)",
      lista, anterior, filtro, lista, atual, filtro))$n[[1]]
    so_depois <- dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM (SELECT %s FROM %s WHERE %s EXCEPT SELECT %s FROM %s WHERE %s)",
      lista, atual, filtro, lista, anterior, filtro))$n[[1]]
    data.frame(recurso = endpoint, desde = if (endpoint == "DatasReferencia") "tudo" else config$desde,
               linhas_antes = antes, linhas_depois = depois,
               registros_removidos_ou_revisados = so_antes,
               registros_adicionados_ou_revisados = so_depois)
  })
  write.csv(do.call(rbind, revisoes), file.path(dir_m, "revisoes.csv"), row.names = FALSE)
  dbExecute(con, "DETACH DATABASE anterior")
}

refs <- read.csv("R/referencias_focus.csv", stringsAsFactors = FALSE, na.strings = "")
comparacao <- lapply(seq_len(nrow(refs)), function(i) {
  r <- refs[i, ]; col <- if (is.na(r$periodo)) "Suavizada" else "DataReferencia"
  alvo <- if (is.na(r$periodo)) r$suavizada else r$periodo
  q <- sprintf("SELECT Mediana, numeroRespondentes FROM %s WHERE Indicador=? AND Data=? AND baseCalculo=? AND %s=?",
    dbQuoteIdentifier(con, r$recurso), dbQuoteIdentifier(con, col))
  v <- dbGetQuery(con, q, params = list(r$indicador, r$data, r$baseCalculo, alvo))
  r$mediana_api <- if (nrow(v) == 1L) v$Mediana else NA_real_
  r$respondentes_api <- if (nrow(v) == 1L) v$numeroRespondentes else NA_integer_
  r$passou <- nrow(v) == 1L && round(r$mediana_api, 2) == r$mediana_pdf && r$respondentes_api == r$respondentes_pdf
  r
})
comparacao <- do.call(rbind, comparacao)
write.csv(comparacao, file.path(dir_m, "comparacao_focus.csv"), row.names = FALSE, na = "")
integridade <- dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]]
stopifnot(integridade == "ok", all(valid$chaves_duplicadas_grupos == 0), all(valid$datas_invalidas == 0),
          all(valid$tipos_numericos_invalidos == 0), all(comparacao$passou))
dbExecute(con, "UPDATE _execucao SET status='validada', validado_utc=? WHERE coleta=?",
          params = list(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), coleta))
dbDisconnect(con)

tamanho_dir <- function(path) {
  f <- list.files(path, recursive = TRUE, full.names = TRUE)
  if (!length(f)) return(0)
  x <- file.info(f); sum(x$size[!x$isdir], na.rm = TRUE)
}
livre <- as.numeric(strsplit(trimws(system2("df", c("-Pk", "."), stdout = TRUE)[[2]]), "[[:space:]]+")[[1]][[4]]) * 1024
resumo <- list(coleta = coleta, modo = config$modo, validado_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  recursos = nrow(valid), janelas = sum(valid$janelas), paginas = total_paginas,
  linhas = sum(valid$linhas_sqlite), linhas_novas = sum(valid$linhas_novas),
  comparacoes_focus = sum(comparacao$passou), integridade_sqlite = integridade,
  bruto_bytes = tamanho_dir(dir_b), sqlite_bytes = file.info(banco)$size, livre_bytes = livre,
  schema_alterado_desde_piloto = config$schema_sha256 != "11d878877403dc8a99666686fc666b005fd04201e224dc65ff77faad28cccfc1")
write_json(resumo, file.path(dir_m, "resumo_historico.json"), pretty = TRUE, auto_unbox = TRUE)
tmp <- tempfile(tmpdir = "dados")
write_json(list(coleta = coleta, banco = banco, manifestos = dir_m, validado_utc = resumo$validado_utc),
           tmp, pretty = TRUE, auto_unbox = TRUE)
stopifnot(file.rename(tmp, "dados/atual.json"))
cat("Validacao historica OK:", resumo$linhas, "linhas em", resumo$paginas, "paginas.\n")
