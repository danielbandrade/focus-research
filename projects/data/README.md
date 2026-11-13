# Local IPCA data

The CSV files in this directory are local research inputs and generated data. Git ignores them. The Focus SQLite snapshot is also local under `dados/`.

From the repository root, restore the R dependencies and rebuild the data:

```sh
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript R/carga_historica.R iniciar
Rscript projects/download_ibge_ipca.R
```

The Focus command creates `dados/atual.json` and a local SQLite snapshot. The IBGE command downloads the national IPCA index from [SIDRA table 1737, variable 2266](https://apisidra.ibge.gov.br/values/t/1737/n1/all/v/2266/p/200012-202512) and writes:

- `ibge_ipca_monthly_index_200110_202512.csv`, used by the rolling forecast notebooks.
- `ibge_ipca_annual_2001_2025.csv`, used by the annual forecast notebook.

Run `projects/ipca_rolling_horizon_comparison.ipynb` with the R kernel to recreate `ipca_rolling_horizon_comparison_200111_202501.csv`. The notebook checks the expected month coverage before calculating results. It also includes static figure previews in `projects/figures/`.

Run `projects/ipca_focus_vs_ar1_comparison.ipynb` after that comparison notebook to recreate `ipca_focus_vs_ar1_200611_202501.csv`, the matched Focus and AR(1) forecast panel.

Run `projects/ipca_quarterly_agent_comparison.ipynb` after the rolling Focus panel notebook to recreate `ipca_quarterly_agent_comparison_200701_202501.csv`. It refits an AR(1) rule once per quarter and compares 73 matched quarterly origins with Focus at 3, 6, and 12 months.

The data are public, but a fresh download may reflect revisions to the official series. The results currently shown in the notebooks use the Focus snapshot `20261029T204913Z` and IBGE data downloaded in November 2026.
