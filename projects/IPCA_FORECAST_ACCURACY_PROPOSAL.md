# Project Proposal: Rolling IPCA Forecast Accuracy and Forecaster Disagreement

**Course:** Simulation of Complex Systems I  
**Presentation:** December 14, 2026  
**Final report:** December 18, 2026

## 1. Research Question

**How does the historical accuracy of Focus-based forecasts of cumulative Brazilian inflation (IPCA) differ across rolling 3-, 6-, and 12-month horizons, and is greater disagreement in the published 12-month Focus forecasts associated with larger subsequent errors?**

At each monthly forecast date, compare the forecast with IPCA realized over the next 3, 6, or 12 calendar months. The main measures are signed and absolute error, in percentage points. Compare horizons on the same forecast months. Separately, relate the published 12-month forecast dispersion to the absolute error of the published 12-month median. These are descriptive associations, not causal claims.

The forecasts used in the three-horizon comparison are **constructed by compounding published monthly Focus medians**. They are not medians of institution-level cumulative forecasts. The BCB's published 12-month median is retained as a distinct benchmark.

## 2. Why Simulation?

Rolling realized windows overlap, so neighboring monthly errors are dependent. A **paired moving-block bootstrap** resamples contiguous blocks of forecast months, preserving much of this time dependence and the pairing of the three horizons within each month. Monte Carlo draws give uncertainty intervals for differences in mean absolute error (MAE) and for the association between published 12-month disagreement and subsequent error, without requiring normally distributed errors.

The simulation measures uncertainty in historical summaries. It does not generate new inflation paths or turn the published cross-sectional standard deviation into a predictive interval for realized IPCA.

## 3. Proposed Methods

1. **Build a common monthly panel.** Use the last available Focus date in each month from November 2001 through January 2025. Obtain monthly IPCA median forecasts for that month and the next 11. Require complete forecasts and anchors no more than seven days before month-end. The validated panel has **279 months**, each with 12 monthly medians.
2. **Construct cumulative forecasts.** For horizon `h` of 3, 6, or 12 months, calculate `100 × [product(1 + monthly_forecast/100) − 1]` from the first `h` monthly medians. Keep the constructed 12-month series separate from the published 12-month median.
3. **Calculate realized inflation.** Use the [IBGE national monthly IPCA index, SIDRA table 1737](https://sidra.ibge.gov.br/tabela/1737). Divide the index at the end of the forecast's last month by the index at the end of the month before the anchor; subtract one and multiply by 100.
4. **Describe and compare errors.** Calculate forecast minus realized IPCA, absolute error, bias, MAE, median and 90th-percentile absolute error, standard deviations, and empirical CDFs. Plot forecast versus realized values and error distributions. Report MAE per month as a descriptive scale check. Raw cumulative MAE grows partly because longer horizons cover more inflation; it does not alone rank forecasting skill.
5. **Use the published 12-month benchmark.** Match `ExpectativasMercadoInflacao12Meses` with `Suavizada = 'N'` on the exact anchor dates. Compare the published and constructed 12-month medians. Relate published `DesvioPadrao` to the published median's subsequent absolute error with a scatter plot and Spearman correlation. Comparable respondent-level cumulative dispersion is unavailable for the constructed 3- and 6-month series.
6. **Simulate uncertainty.** Use a recorded seed and **10,000 paired circular moving-block bootstrap draws** with 12-month blocks. Resample complete matched rows; recompute MAE differences (6 minus 3, 12 minus 6, and 12 minus 3 months) and the 12-month disagreement–error Spearman correlation. Report percentile 95% intervals, fractions of positive MAE differences, and convergence at 1,000, 5,000, and 10,000 draws. Examine block-length or period sensitivity before strongly interpreting intervals.

All calculations and figures are implemented in **R** in the [comparison notebook](ipca_rolling_horizon_comparison.ipynb), which records the matching rules and simulation seed.

## 4. Data and Parameters

| Numeric feature | Meaning | Source |
| --- | --- | --- |
| Monthly `Mediana` | Forecast of each month's IPCA change (%) | `ExpectativaMercadoMensais` in the [validated Focus snapshot](../RELATORIO_HISTORICO.md) |
| Constructed cumulative forecast | Compounded monthly medians over 3, 6, or 12 months (%) | Derived from monthly Focus medians |
| Published 12-month `Mediana` | BCB's rolling 12-month Focus forecast (%) | `ExpectativasMercadoInflacao12Meses` in the same snapshot |
| Published 12-month `DesvioPadrao` | Dispersion of submitted 12-month forecasts (p.p.) | Same BCB resource |
| Realized cumulative IPCA | Observed forward 3-, 6-, or 12-month inflation (%) | [IBGE SIDRA table 1737](https://sidra.ibge.gov.br/tabela/1737), monthly index |

Focus filters are `Indicador = 'IPCA'`, `baseCalculo = 0`, and, for the published 12-month series, `Suavizada = 'N'`. The local Focus snapshot is `20261029T204913Z`. The local IBGE index has 291 consecutive months from October 2001 through December 2025. The generated matched panel has 279 complete monthly anchors, both versions of the 12-month forecast, realized values, errors, and published 12-month dispersion. Both CSVs are excluded from Git; see the [data rebuild instructions](data/README.md). This exceeds the assignment's three-numeric-feature minimum.

The main acquisition limits are aggregate Focus statistics rather than institution-level predictions, possible historical data revisions, and overlap among monthly errors. The report will document dates, units, missingness, and the difference between constructed and published forecasts. It will assess whether PCA of standardized numeric features adds an interpretable *descriptive* view; PCA is not needed for the primary question. See [BCB Focus documentation](https://www.bcb.gov.br/controleinflacao/expectativasmercado) and [IBGE IPCA documentation](https://www.ibge.gov.br/estatisticas/economicas/precos-e-custos/9256-indice-de-precos-ao-consumidor-amplo.html).

## 5. Expected Outputs

- A reproducible panel and table of bias, MAE, median and upper-tail absolute error for each horizon.
- Empirical CDFs and error plots, including assessment of distribution shape and normal approximation.
- A comparison of constructed and published 12-month forecasts.
- A scatter plot and rank correlation relating published 12-month disagreement to published 12-month absolute error.
- Paired block-bootstrap distributions, confidence intervals, and convergence diagnostics.
- A discussion of overlapping windows, horizon scale, regime dependence, revisions, and aggregate-data limits.

## 6. Timeline: Weeks 13–15

| Week | Milestone |
| --- | --- |
| **13** | Validate Focus and IBGE sources; match monthly anchors; check dates, completeness, units, and missing values. |
| **14** | Complete horizon comparison, empirical CDFs, 12-month benchmark, disagreement analysis, bootstrap, and sensitivity checks. |
| **15** | Prepare the **6–8 slide, 10-minute presentation for December 14** and the **6–8 page article by December 18**, with figures, references, convergence diagnostics, R code, and an explanation of AI use. |

The article will follow the required **Abstract, Introduction, Methods, Results, Discussion, References, Appendix, and Implementation** structure in [PROJECT_INSTRUCTIONS.md](PROJECT_INSTRUCTIONS.md).
