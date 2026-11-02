#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(DBI); library(RSQLite); library(jsonlite)})
versao <- fromJSON("dados/atual.json")
recurso <- "ExpectativasMercadoAnuais"
indicador <- "IPCA"
estatistica <- "Mediana"
periodo <- "2027"
base_calculo <- 0L
con <- dbConnect(SQLite(), versao$banco)
serie <- dbGetQuery(con, "
  SELECT Data, Mediana, DataReferencia, baseCalculo, coleta
  FROM ExpectativasMercadoAnuais
  WHERE Indicador = ? AND IndicadorDetalhe IS NULL
    AND DataReferencia = ? AND baseCalculo = ?
  ORDER BY Data", params = list(indicador, periodo, base_calculo))
dbDisconnect(con)
cat("Versao:", versao$coleta, "| Recurso:", recurso, "| Indicador:", indicador,
    "| Estatistica:", estatistica, "| Periodo:", periodo,
    "| baseCalculo:", base_calculo, "| Pontos:", nrow(serie), "\n")
print(head(serie, 3))
print(tail(serie, 3))
print(sessionInfo())
