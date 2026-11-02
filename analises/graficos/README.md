# Gráficos de exemplo

Gerados a partir do snapshot lógico `20261029T204913Z`, indicado em `dados/atual.json`, por [graficos_exemplo.R](../graficos_exemplo.R). Para refazer com o snapshot atual:

```sh
Rscript analises/graficos_exemplo.R
```

| Arquivo | Consulta e leitura |
| --- | --- |
| [ipca_anos_alvo.png](ipca_anos_alvo.png) | `ExpectativasMercadoAnuais`; `Indicador = IPCA`, `IndicadorDetalhe IS NULL`, `baseCalculo = 0`, `Mediana`; anos projetados 2026, 2027 e 2028 fixos, observações desde 01/01/2024. Cada linha mantém um único `DataReferencia`. |
| [selic_2027_bases.png](selic_2027_bases.png) | Mesmo recurso; `Indicador = Selic`, `DataReferencia = 2027`, `Mediana`; compara os códigos nativos `baseCalculo = 0` e `1` em observações desde 01/01/2025. |
| [ipca_12m_suavizacao.png](ipca_12m_suavizacao.png) | `ExpectativasMercadoInflacao12Meses`; `Indicador = IPCA`, `baseCalculo = 0`, `Mediana`; compara `Suavizada = S` e `N` desde 01/01/2024. É um horizonte móvel de 12 meses. |

O eixo horizontal é sempre a data da observação (`Data`), não a data de publicação do PDF Focus. As consultas trazem apenas as colunas e linhas necessárias do SQLite. Ausências não são convertidas em zero; o script interrompe se a seleção tiver mediana ausente ou chave repetida.
