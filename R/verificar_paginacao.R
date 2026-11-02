#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(httr2); library(jsonlite)})
args <- commandArgs(trailingOnly = TRUE)
coleta <- if (length(args)) args[[1]] else tail(sort(basename(list.dirs("dados/manifestos", recursive = FALSE))), 1)
dir_m <- file.path("dados/manifestos", coleta)
inv <- fromJSON(file.path(dir_m, "inventario.json"), simplifyVector = FALSE)
base <- "https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata"
montar <- function(endpoint, parametros) {
  pares <- paste0(URLencode(names(parametros), reserved = TRUE), "=",
                  vapply(parametros, URLencode, character(1), reserved = TRUE))
  paste0(base, "/", endpoint, "?", paste(pares, collapse = "&"))
}
resultado <- lapply(names(inv), function(endpoint) {
  m <- fromJSON(file.path(dir_m, paste0(endpoint, ".json")), simplifyVector = FALSE)
  stopifnot(is.null(m$erro), length(m$paginas) > 0)
  ordem <- paste(names(inv[[endpoint]]$campos), collapse = ",")
  u <- montar(endpoint, list("$filter" = m$paginas[[1]]$filtro,
                             "$orderby" = ordem, "$top" = "1", "$skip" = as.character(m$linhas),
                             "$format" = "json"))
  resp <- req_perform(request(u) |> req_timeout(90) |> req_retry(max_tries = 4))
  v <- fromJSON(rawToChar(resp_body_raw(resp)), simplifyDataFrame = TRUE)$value
  n <- if (is.data.frame(v)) nrow(v) else if (!length(v)) 0L else stop("value inesperado")
  data.frame(recurso = endpoint, skip = m$linhas, linhas_apos_ultima = n,
             conferido_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             url = u)
})
resultado <- do.call(rbind, resultado)
write.csv(resultado, file.path(dir_m, "paginacao.csv"), row.names = FALSE)
cat(sum(resultado$linhas_apos_ultima == 0), "/ 13 recursos terminam apos a ultima pagina.\n")
stopifnot(nrow(resultado) == 13L, all(resultado$linhas_apos_ultima == 0))
