#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(DBI); library(RSQLite); library(httr2); library(digest)})
args <- commandArgs(trailingOnly = TRUE)
coleta <- if (length(args)) args[[1]] else tail(sort(basename(list.dirs("dados/manifestos", recursive = FALSE))), 1)
con <- dbConnect(SQLite(), file.path("dados", paste0("focus-piloto-", coleta, ".sqlite")))
refs <- read.csv("R/referencias_focus.csv", stringsAsFactors = FALSE, na.strings = "")
for (nome in unique(refs$pdf)) {
  arquivo <- file.path("dados/manifestos", coleta, nome)
  if (!file.exists(arquivo)) {
    fonte <- paste0("https://www.bcb.gov.br/content/focus/focusmarketreadout/", nome)
    bytes <- resp_body_raw(req_perform(request(fonte) |> req_timeout(90) |> req_retry(max_tries = 4)))
    stopifnot(identical(rawToChar(bytes[1:4]), "%PDF"))
    writeBin(bytes, arquivo)
  }
}
resultado <- lapply(seq_len(nrow(refs)), function(i) {
  r <- refs[i, ]
  stopifnot(file.exists(file.path("dados/manifestos", coleta, r$pdf)))
  col <- if (is.na(r$periodo)) "Suavizada" else "DataReferencia"
  alvo <- if (is.na(r$periodo)) r$suavizada else r$periodo
  q <- sprintf("SELECT Mediana, numeroRespondentes FROM %s WHERE Indicador = ? AND Data = ? AND baseCalculo = ? AND %s = ?",
               dbQuoteIdentifier(con, r$recurso), dbQuoteIdentifier(con, col))
  valor <- dbGetQuery(con, q, params = list(r$indicador, r$data, r$baseCalculo, alvo))
  stopifnot(nrow(valor) == 1L)
  r$mediana_api <- valor$Mediana
  r$respondentes_api <- valor$numeroRespondentes
  r$fonte_pdf_url <- paste0("https://www.bcb.gov.br/content/focus/focusmarketreadout/", r$pdf)
  r$pdf_sha256 <- digest(file = file.path("dados/manifestos", coleta, r$pdf), algo = "sha256")
  r$passou <- round(r$mediana_api, 2) == r$mediana_pdf &&
    r$respondentes_api == r$respondentes_pdf
  r
})
resultado <- do.call(rbind, resultado)
dbDisconnect(con)
write.csv(resultado, file.path("dados/manifestos", coleta, "comparacao_focus.csv"), row.names = FALSE, na = "")
cat(sum(resultado$passou), "/", nrow(resultado), "comparacoes com PDFs oficiais passaram.\n")
stopifnot(all(resultado$passou))
