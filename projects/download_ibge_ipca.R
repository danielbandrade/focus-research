# Rebuild the local IBGE inputs used by the IPCA forecast notebooks.
source_url <- paste0(
  "https://apisidra.ibge.gov.br/values/t/1737/n1/all/v/2266/p/",
  "200012-202512"
)

raw <- jsonlite::fromJSON(source_url)
if (!is.data.frame(raw) || nrow(raw) < 2L || !"V" %in% names(raw)) {
  stop("Unexpected SIDRA response")
}
data <- raw[-1L, , drop = FALSE] # The first row describes the API columns.
expected <- format(seq(as.Date("2000-12-01"), as.Date("2025-12-01"), by = "month"), "%Y%m")
month_columns <- names(data)[vapply(data, function(column) {
  identical(sort(as.character(column)), expected)
}, logical(1))]
if (length(month_columns) != 1L) stop("Could not identify the monthly period column")

month <- as.character(data[[month_columns]])
index <- as.numeric(gsub(",", ".", as.character(data$V), fixed = TRUE))
if (anyNA(index) || any(index <= 0)) stop("Missing or invalid IPCA index values")
order_month <- order(month)
month <- month[order_month]
index <- index[order_month]
if (!identical(month, expected)) stop("Incomplete monthly IPCA index")

output_dir <- file.path("projects", "data")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
monthly <- data.frame(month = month[month >= "200110"],
                      ipca_index = index[month >= "200110"])
writeLines(c("month,ipca_index",
             sprintf("%s,%.2f", monthly$month, monthly$ipca_index)),
           file.path(output_dir, "ibge_ipca_monthly_index_200110_202512.csv"))

names(index) <- month
years <- 2001:2025
annual <- data.frame(
  year = years,
  realized_ipca_pct = round(100 * (
    index[paste0(years, "12")] / index[paste0(years - 1L, "12")] - 1
  ), 2)
)
writeLines(c("year,realized_ipca_pct",
             sprintf("%d,%.2f", annual$year, annual$realized_ipca_pct)),
           file.path(output_dir, "ibge_ipca_annual_2001_2025.csv"))
cat("Saved", nrow(monthly), "monthly and", nrow(annual), "annual IPCA values in", output_dir, "\n")
