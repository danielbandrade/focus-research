# Project Proposal: Forecast Horizon, Disagreement, and IPCA Forecast Accuracy

**Course:** Simulation of Complex Systems I  
**Presentation:** December 14, 2026  
**Final report:** December 18, 2026

## 1. Research Question

**How does the accuracy of the Focus median forecast for annual Brazilian inflation (IPCA) change as the target year approaches, and does greater disagreement among forecasters signal a larger eventual forecast error?**

The primary outcome is the absolute difference, in percentage points, between a Focus forecast and the realized annual IPCA. The project will compare forecasts made approximately 12, 6, and 3 months before the end of each target year. Within each horizon, it will examine whether the published cross-sectional standard deviation of forecasts is associated with the eventual error.

Two testable expectations guide the analysis:

1. Forecast errors tend to become smaller as the target year approaches.
2. Forecasts made when respondents disagree more tend to have larger eventual errors, even when the forecast horizon is held fixed.

These are empirical associations, not claims that disagreement causes forecast errors. Either expectation may be rejected by the data.

## 2. Why Simulation?

The number of completed target years is limited, and forecast errors from the three horizons of the same year are related. A Monte Carlo **paired bootstrap by target year** can quantify how much the observed differences depend on which historical years happen to be included. Resampling complete years retains the connection among the 12-, 6-, and 3-month forecasts for each year. It also produces empirical uncertainty intervals without assuming normally distributed errors.

The simulation will estimate the distribution of (a) the change in mean absolute error between horizons and (b) the association between disagreement and error within a horizon. The simulation describes uncertainty about historical patterns; it does not generate or evaluate individual forecasters' predictions.

## 3. Proposed Methods

1. **Construct a matched historical panel.** For each completed target year from **2001 through 2025**, select the latest available Focus observation on or before three prespecified dates: December 31 of the preceding year (about 12 months before year-end), June 30 of the target year (about 6 months), and September 30 of the target year (about 3 months). Never select a forecast made after its checkpoint.
2. **Join realized inflation.** Match `DataReferencia` to the same year's realized national annual IPCA, using the December **year-to-date percentage change** from [IBGE's IPCA historical series](https://sidra.ibge.gov.br/tabela/1737). Keep both forecasts and realized values in percent, so their difference is in percentage points.
3. **Describe the data.** Check missing values, dates, units, and duplicates. Calculate signed error (`forecast − realized`) and absolute error. Report counts, means, medians, quantiles, standard deviations, and correlations by horizon. Plot forecast versus realized IPCA, histograms and box plots of errors, and empirical CDFs of absolute errors. Examine the shapes of the error distributions before using any normal approximation. Assess whether PCA of standardized numeric variables adds an interpretable descriptive view; PCA is not needed for the main comparison.
4. **Compare horizons.** Calculate mean and median absolute error at each checkpoint and paired differences for the same target years. Use the empirical CDFs to compare the entire error distribution, including its upper tail.
5. **Examine disagreement.** Within each horizon, relate the Focus `DesvioPadrao` to the eventual absolute error using scatter plots, Spearman correlation, and comparisons between lower- and higher-disagreement observations. Treat `DesvioPadrao` as *dispersion across submitted forecasts*, not as a calibrated probability interval for the realized IPCA.
6. **Simulate uncertainty.** With a recorded random seed, draw **10,000 bootstrap samples of target years** with replacement. Each sampled year contributes its three matched forecasts and realized outcome. Recompute the paired horizon differences and disagreement statistics for every sample. Report percentile intervals, the fraction of simulations supporting each direction, and convergence checks at increasing numbers of draws. Repeat the analysis excluding unusually influential years to assess sensitivity.

All extraction, analysis, figures, and simulations will be implemented in **R**. The final code will record data sources, filters, checkpoint rules, package versions, and the simulation seed.

## 4. Data and Parameters

| Numeric feature | Meaning | Source |
| --- | --- | --- |
| `Mediana` | Focus median forecast of annual IPCA (%) | `ExpectativasMercadoAnuais` in the [local Focus snapshot](../RELATORIO_HISTORICO.md) |
| `DesvioPadrao` | Dispersion of submitted annual IPCA forecasts (percentage points) | Same Focus resource |
| Realized annual IPCA | Observed inflation for the target year (%) | [IBGE IPCA, SIDRA table 1737](https://sidra.ibge.gov.br/tabela/1737) |
| Forecast horizon | Approximate months remaining until target year-end (12, 6, or 3) | Derived from the prespecified checkpoints |

Focus filters: `Indicador = 'IPCA'`, `IndicadorDetalhe IS NULL`, `baseCalculo = 0`, and `DataReferencia` equal to the target year. In the validated local snapshot `20261029T204913Z`, the three Focus checkpoints have nonmissing `Mediana` and `DesvioPadrao` for **25 target years (75 forecast records)**. This count describes the Focus side only; the final joined sample will be verified after importing the IBGE series. Years **2026 onward are excluded** because their annual IPCA outcomes were not complete at the snapshot date.

The `numeroRespondentes` field is unavailable at many older checkpoints. It will therefore **not** be required for the main analysis. An optional sensitivity check can examine respondent count for the fully observed **2015–2025** subset without replacing the primary 25-year sample.

Limitations to report include the small number of independent target years, changes in economic conditions across decades, possible revisions to published series, and the fact that Focus provides aggregate statistics rather than individual forecasts. The [BCB Focus documentation](https://www.bcb.gov.br/controleinflacao/expectativasmercado) and the [IBGE IPCA documentation](https://www.ibge.gov.br/estatisticas/economicas/precos-e-custos/9256-indice-de-precos-ao-consumidor-amplo.html) will be cited for definitions and provenance.

## 5. Expected Outputs

- A reproducible dataset with one row per target year and forecast horizon, plus the realized IPCA and error measures.
- A table comparing signed bias, mean absolute error, median absolute error, and error quantiles at 12, 6, and 3 months.
- Empirical CDFs and box plots showing how forecast-error distributions change with horizon.
- Scatter plots and rank correlations showing the observed relationship between forecast dispersion and eventual absolute error at each horizon.
- Bootstrap distributions, uncertainty intervals, and convergence diagnostics for both research claims.
- A discussion of whether shorter horizons and greater disagreement are useful indicators of historical forecast accuracy, with limitations clearly stated.

No direction or size of an effect is assumed in advance; these are outputs to be measured.

## 6. Timeline: Weeks 13–15

| Week | Milestone |
| --- | --- |
| **13** | Import the IBGE realized IPCA series; extract Focus checkpoints; validate the join and describe missing values and distributions. |
| **14** | Produce error comparisons, empirical CDFs, disagreement analysis, and the paired bootstrap; check convergence and sensitivity. |
| **15** | Prepare the **6–8 slide, 10-minute presentation for December 14**; finalize the **6–8 page article by December 18** with figures, references, R code, and an explanation of AI use. |

The final article will follow the required **Abstract, Introduction, Methods, Results, Discussion, References, Appendix, and Implementation** structure in [PROJECT_INSTRUCTIONS.md](PROJECT_INSTRUCTIONS.md). Its results section will distinguish descriptive statistics, simulation output, convergence diagnostics, and uncertainty estimates.
