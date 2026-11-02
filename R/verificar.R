#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(jsonlite)
  library(DBI)
  library(RSQLite)
  library(digest)
})

args <- commandArgs(trailingOnly = TRUE)
coleta <- if (length(args)) args[[1]] else tail(sort(basename(list.dirs("dados/manifestos", recursive = FALSE))), 1)
dir_m <- file.path("dados/manifestos", coleta)
dir_b <- file.path("dados/bruto", coleta)
inventario <- fromJSON(file.path(dir_m, "inventario.json"), simplifyVector = FALSE)
stopifnot(length(inventario) == 13L)
origem <- dbConnect(SQLite(), file.path("dados", paste0("focus-piloto-", coleta, ".sqlite")))
destino_arquivo <- tempfile(fileext = ".sqlite")
destino <- dbConnect(SQLite(), destino_arquivo)

for (endpoint in names(inventario)) {
  inv <- inventario[[endpoint]]
  man <- fromJSON(file.path(dir_m, paste0(endpoint, ".json")), simplifyVector = FALSE)
  stopifnot(is.null(man$erro), man$paginas_com_erro == 0L)
  campos <- unlist(inv$campos, use.names = TRUE)
  tipos <- setNames(ifelse(campos == "Edm.Int32", "INTEGER",
                           ifelse(campos == "Edm.Decimal", "REAL", "TEXT")), names(campos))
  dbCreateTable(destino, endpoint, c(tipos, recurso = "TEXT", coleta = "TEXT"))
  linhas <- 0L
  for (p in man$paginas) {
    arquivo <- file.path(dir_b, endpoint, p$arquivo)
    stopifnot(file.exists(arquivo),
              identical(digest(file = arquivo, algo = "sha256"), p$sha256))
    comprimido <- readBin(arquivo, "raw", n = file.info(arquivo)$size)
    resposta <- memDecompress(comprimido, type = "gzip")
    stopifnot(length(resposta) == p$bytes_json)
    dados <- fromJSON(rawToChar(resposta), simplifyDataFrame = TRUE)$value
    stopifnot(nrow(dados) == p$linhas)
    if (nrow(dados)) {
      stopifnot(setequal(names(dados), names(campos)))
      dados <- dados[names(campos)]
      dados$recurso <- endpoint
      dados$coleta <- coleta
      dbAppendTable(destino, endpoint, dados)
    }
    linhas <- linhas + nrow(dados)
  }
  stopifnot(linhas == man$linhas)
  ordem <- paste(as.character(dbQuoteIdentifier(origem, names(campos))), collapse = ",")
  sql <- sprintf("SELECT * FROM %s ORDER BY %s", dbQuoteIdentifier(origem, endpoint), ordem)
  stopifnot(identical(dbGetQuery(origem, sql), dbGetQuery(destino, sql)))
  cat(endpoint, linhas, "linhas, hashes e reconstrucao OK\n")
}
cat("13 recursos reconstruidos a partir dos JSON compactados.\n")
dbDisconnect(origem)
dbDisconnect(destino)
write_json(list(coleta = coleta, banco_temporario_reconstrucao_bytes = file.info(destino_arquivo)$size,
                banco_temporario_removido = TRUE),
           file.path(dir_m, "verificacao_reconstrucao.json"), pretty = TRUE, auto_unbox = TRUE)
unlink(destino_arquivo)
