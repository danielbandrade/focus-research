#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(DBI); library(RSQLite); library(jsonlite)})

versao <- fromJSON("dados/atual.json")
con <- dbConnect(SQLite(), versao$banco)
on.exit(dbDisconnect(con), add = TRUE)
saida <- "analises/graficos"
dir.create(saida, recursive = TRUE, showWarnings = FALSE)

abrir_png <- function(nome) {
  png(file.path(saida, nome), width = 11.2, height = 6.3, units = "in", res = 160,
      type = if (Sys.info()[["sysname"]] == "Darwin") "quartz" else "cairo", bg = "white")
  par(family = "sans", mar = c(5.7, 5.6, 4.8, 1.3), mgp = c(3.2, 0.8, 0),
      las = 1, cex.axis = 0.9, cex.lab = 1.05, fg = "#334155")
}
base_grafico <- function(datas, valores, titulo, subtitulo, inicio, fim,
                         passo = "6 months", unidade = "Mediana (%)") {
  limites <- as.Date(c(as.character(inicio), as.character(fim)))
  ylim <- range(valores, na.rm = TRUE)
  folga <- diff(ylim) * 0.1
  if (folga == 0) folga <- 0.1
  ylim <- ylim + c(-folga, folga)
  plot(limites, c(0, 1), type = "n", axes = FALSE,
       xlim = limites, ylim = ylim, xlab = "Data da observação", ylab = unidade)
  marcas_y <- pretty(ylim, n = 6)
  abline(h = marcas_y, col = "#E5EAF0", lwd = 1)
  axis(2, at = marcas_y, col.axis = "#475569", col = "#94A3B8")
  axis.Date(1, at = seq(limites[[1]], limites[[2]], by = passo), format = "%m/%Y",
            col.axis = "#475569", col = "#94A3B8")
  box(bty = "l", col = "#94A3B8")
  mtext(titulo, side = 3, line = 2.7, adj = 0, cex = 1.5, font = 2, col = "#0F172A")
  mtext(subtitulo, side = 3, line = 1.2, adj = 0, cex = 0.86, col = "#475569")
}
rodape <- function(texto) {
  mtext(paste0("BCB/Olinda • snapshot ", versao$coleta, " • ", texto), side = 1,
        line = 4.25, adj = 0, cex = 0.72, col = "#64748B")
}
checar <- function(dados, dimensoes) {
  stopifnot(nrow(dados) > 0L, !anyNA(dados$Mediana),
            !anyDuplicated(dados[dimensoes]))
  dados$Data <- as.Date(dados$Data)
  stopifnot(!anyNA(dados$Data))
  dados
}

# 1. Cada cor mantém fixo o ano projetado; não há emenda de horizontes.
ipca <- dbGetQuery(con, "
  SELECT Data, DataReferencia, Mediana
  FROM ExpectativasMercadoAnuais
  WHERE Indicador = ? AND IndicadorDetalhe IS NULL AND baseCalculo = ?
    AND Data >= ? AND DataReferencia IN ('2026','2027','2028')
  ORDER BY Data, DataReferencia", params = list("IPCA", 0L, "2024-01-01"))
ipca <- checar(ipca, c("Data", "DataReferencia"))
abrir_png("ipca_anos_alvo.png")
base_grafico(ipca$Data, ipca$Mediana, "Expectativas para o IPCA",
             "Mediana agregada diária por ano projetado • baseCalculo = 0",
             "2024-01-01", max(ipca$Data))
cores <- c("2026" = "#1D4ED8", "2027" = "#0F766E", "2028" = "#D97706")
for (ano in names(cores)) {
  d <- ipca[ipca$DataReferencia == ano, ]
  lines(d$Data, d$Mediana, col = cores[[ano]], lwd = 2.6)
}
legend("topleft", legend = names(cores), col = unname(cores), lwd = 2.6,
       horiz = TRUE, bty = "n", cex = 0.96, inset = 0.02)
rodape("ExpectativasMercadoAnuais • IPCA • Mediana • DataReferencia fixa por linha")
dev.off()

# 2. As bases nativas são exibidas separadas, sem lhes atribuir nome novo.
selic <- dbGetQuery(con, "
  SELECT Data, baseCalculo, Mediana
  FROM ExpectativasMercadoAnuais
  WHERE Indicador = ? AND IndicadorDetalhe IS NULL AND DataReferencia = ?
    AND Data >= ? AND baseCalculo IN (0,1)
  ORDER BY Data, baseCalculo", params = list("Selic", "2027", "2025-01-01"))
selic <- checar(selic, c("Data", "baseCalculo"))
abrir_png("selic_2027_bases.png")
base_grafico(selic$Data, selic$Mediana, "Expectativas para a Selic de 2027",
             "Mediana agregada diária • comparação das duas bases de cálculo do BCB",
             "2025-01-01", max(selic$Data), "3 months", "Mediana (% a.a.)")
for (base in c(0L, 1L)) {
  d <- selic[selic$baseCalculo == base, ]
  lines(d$Data, d$Mediana, col = if (base == 0L) "#1D4ED8" else "#D97706",
        lwd = 2.5, lty = if (base == 0L) 1 else 2)
}
legend("topleft", legend = c("baseCalculo = 0", "baseCalculo = 1"),
       col = c("#1D4ED8", "#D97706"), lwd = 2.5, lty = c(1, 2),
       bty = "n", cex = 0.96, inset = 0.02)
rodape("ExpectativasMercadoAnuais • Selic • DataReferencia = 2027 • Mediana")
dev.off()

# 3. Horizonte móvel de 12 meses: Suavizada é dimensão nativa.
inflacao <- dbGetQuery(con, "
  SELECT Data, Suavizada, Mediana
  FROM ExpectativasMercadoInflacao12Meses
  WHERE Indicador = ? AND baseCalculo = ? AND Data >= ? AND Suavizada IN ('S','N')
  ORDER BY Data, Suavizada", params = list("IPCA", 0L, "2024-01-01"))
inflacao <- checar(inflacao, c("Data", "Suavizada"))
suave <- inflacao[inflacao$Suavizada == "S", c("Data", "Mediana")]
nao <- inflacao[inflacao$Suavizada == "N", c("Data", "Mediana")]
pares <- merge(suave, nao, by = "Data", suffixes = c("_S", "_N"))
stopifnot(nrow(pares) == nrow(suave), nrow(pares) == nrow(nao))
abrir_png("ipca_12m_suavizacao.png")
base_grafico(pares$Data, c(pares$Mediana_S, pares$Mediana_N),
             "IPCA projetado para os próximos 12 meses",
             "Medianas diárias com e sem suavização • baseCalculo = 0",
             "2024-01-01", max(pares$Data))
polygon(c(pares$Data, rev(pares$Data)),
        c(pares$Mediana_S, rev(pares$Mediana_N)),
        col = adjustcolor("#0F766E", alpha.f = 0.12), border = NA)
lines(pares$Data, pares$Mediana_S, col = "#0F766E", lwd = 2.6)
lines(pares$Data, pares$Mediana_N, col = "#D97706", lwd = 2.2, lty = 2)
legend("topleft", legend = c("Suavizada = S", "Suavizada = N"),
       col = c("#0F766E", "#D97706"), lwd = c(2.6, 2.2), lty = c(1, 2),
       bty = "n", cex = 0.96, inset = 0.02)
rodape("ExpectativasMercadoInflacao12Meses • IPCA • horizonte móvel • Mediana")
dev.off()

dbDisconnect(con)
cat("Gráficos criados em", normalizePath(saida), "para o snapshot", versao$coleta, "\n")
