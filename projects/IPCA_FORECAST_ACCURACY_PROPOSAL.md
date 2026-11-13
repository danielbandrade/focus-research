# Project Proposal: Quarterly AR(1) and Focus Agents for IPCA Forecasting

**Course:** Simulation of Complex Systems I  
**Presentation:** December 14, 2026  
**Final report:** December 18, 2026

## 1. Research question

**How does a simulated agent that re-estimates an AR(1) inflation rule every quarter compare with an agent that follows Focus median forecasts when predicting Brazilian IPCA over the next 3, 6, and 12 months?**

[Poledna et al. (2023)](https://doi.org/10.1016/j.euroecorev.2022.104306) use simple AR(1) rules for agents' expectations inside an agent-based economy and re-estimate an AR(1) forecast benchmark each quarter. We adapt the rule and update frequency to Brazilian IPCA. This is a comparison of two historical forecasting agents, not a replication of the paper's interacting-agent economy or its Austrian GDP-deflator forecasts.

At each common quarterly origin, the AR(1) agent uses only previously realized inflation. The Focus agent uses the published monthly IPCA medians available at that origin. Both predict cumulative inflation over identical forward windows and are scored against the same IBGE IPCA realization. A secondary analysis of the published Focus 12-month forecast and disagreement remains separate from this agent comparison.

## 2. Why simulation?

The AR(1) agent repeatedly estimates its rule and generates a forward path from its own predictions. Unlike a fixed historical forecast series, its expectations are produced by a specified decision rule at each origin. A paired circular block bootstrap then simulates resamples of the historical forecast episodes to estimate uncertainty in the agents' accuracy difference. Neither step simulates prices changing in response to agents' choices; there are no interacting agents or random AR(1) shocks.

## 3. Proposed methods

1. **Match quarterly origins.** Use the last available Focus observation in January, April, July, and October from **January 2007 through January 2025**: 73 common origins. These first months of calendar quarters align the next 3, 6, and 12 months with 1, 2, and 4 complete quarters. The existing 279-month Focus panel supplies the matched forecasts and outcomes.
2. **Prepare past inflation.** Form quarter-on-quarter log IPCA changes from the national IBGE monthly index at each quarter end. Start with 20 observed quarterly changes from 2002 Q1 through 2006 Q4. At each origin, the previous quarter is the final training observation; its IPCA is assumed published by the last Focus date of the origin month.
3. **Run the AR(1) agent.** Fit `y_q = alpha + phi*y_(q-1) + error_q` by ordinary least squares on an expanding history. Refit once per quarter, recursively predict four quarterly log changes, and convert the first 1, 2, and 4 predicted changes to cumulative percentage inflation. Save each fit's coefficients and training end date to audit the information boundary.
4. **Run the Focus agent.** Compound the published monthly Focus IPCA medians for the same 3, 6, and 12 months (`Indicador = 'IPCA'`, `baseCalculo = 0`). These constructed cumulative paths are not medians of institution-level cumulative forecasts. Keep the BCB's published 12-month series as a distinct descriptive benchmark.
5. **Compare matched errors.** For each agent and horizon, compute forecast minus realized IPCA, bias, mean absolute error (MAE), RMSE, and the paired difference in absolute error. Compare agents within each horizon; longer cumulative windows have a different scale. Inspect distributions and changes over time.
6. **Quantify uncertainty.** Use **10,000 paired circular moving-block bootstrap draws** with four-quarter blocks and seed `20261113`. Resample complete quarterly rows to retain the agents' pairing and some dependence from overlapping 12-month outcomes. Report percentile 95% intervals and the fraction of draws favoring Focus for each horizon. Treat these as uncertainty about the historical accuracy gap, not a guarantee of future superiority.

The [quarterly agent notebook](ipca_quarterly_agent_comparison.ipynb) implements the comparison in R and checks the outcome windows directly against the IBGE index. The [monthly Focus panel notebook](ipca_rolling_horizon_comparison.ipynb) constructs its input. The existing [monthly AR(1) comparison](ipca_focus_vs_ar1_comparison.ipynb) uses a different, monthly refit schedule and is not the main simulation.

## 4. Data and initial result

| Quantity | Meaning | Source |
| --- | --- | --- |
| Monthly Focus `Mediana` | Forecast of each month's IPCA change (%) | `ExpectativaMercadoMensais` in the [validated Focus snapshot](../RELATORIO_HISTORICO.md) |
| Quarterly log IPCA change | AR(1) agent's observed training variable | [IBGE SIDRA table 1737](https://sidra.ibge.gov.br/tabela/1737), quarter-end national index |
| Forward cumulative IPCA | Shared realized outcome over 1, 2, or 4 quarters | Same IBGE index |
| Signed and absolute error | Each agent's forecast minus realized inflation, in percentage points | Derived on the matched origins |

The local Focus snapshot is `20261029T204913Z`; the IBGE index ends in December 2025. The validated comparison has **73 quarterly origins**. Preliminary MAEs (Focus versus AR(1), in percentage points) are **0.396 versus 0.648** at 3 months, **0.866 versus 1.160** at 6 months, and **1.572 versus 1.821** at 12 months. The paired four-quarter-block bootstrap interval for Focus's 12-month MAE gain crosses zero, so that horizon does not show a clear advantage under this uncertainty check.

Focus statistics are aggregates, not individual institution forecasts. The AR(1) agent's information set is narrower than that of Focus respondents. Historical data revisions, inflation-regime changes, the assumed publication lag, and overlapping outcomes limit interpretation. Local input CSVs and generated comparison data are ignored by Git; see [data rebuild instructions](data/README.md).

## 5. Expected outputs

- A reproducible quarterly panel containing both agents' forecasts, fitted AR(1) coefficients, training end dates, realized IPCA, and errors.
- Matched MAE, bias, and RMSE comparisons for 3-, 6-, and 12-month horizons, plus an accuracy figure.
- Paired block-bootstrap intervals for each MAE difference and a discussion of the limits of this agent analogy.
- A separate annual forecast check and published 12-month Focus benchmark as supporting descriptive analyses.

## 6. Timeline: Weeks 13–15

| Week | Milestone |
| --- | --- |
| **13** | Validate the Focus panel, IBGE index, quarterly training dates, and common outcome windows. |
| **14** | Run quarterly agents, compare errors, inspect distributions, and complete the paired bootstrap. |
| **15** | Prepare the **6–8 slide, 10-minute presentation for December 14** and the **6–8 page article by December 18**, including the paper's methodological attribution, limitations, reproducible code, and AI-use statement. |

The article follows the required structure in [PROJECT_INSTRUCTIONS.md](PROJECT_INSTRUCTIONS.md).
