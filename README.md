# Dados Focus em R e SQLite

Este projeto coleta os **13 recursos públicos ativos** do BCB. O [relatório histórico](RELATORIO_HISTORICO.md) traz contagens, cobertura, validações, espaço e limites da carga feita em 29/10/2026. Na pasta de trabalho original, `dados/atual.json` aponta para o snapshot SQLite validado mais recente; o snapshot inicial permanece disponível localmente para auditoria e reversão.

**Clone do GitHub:** toda a pasta `dados/` é ignorada, inclusive bancos, páginas brutas, manifestos e `dados/atual.json`. Para executar as consultas e o notebook em outra máquina, restaure o ambiente R e rode `Rscript R/carga_historica.R iniciar` para gerar um novo snapshot local.

Os CSVs de pesquisa em `projects/data/` também são locais e ignorados pelo Git. Para recriar os dados do IPCA do IBGE, execute `Rscript projects/download_ibge_ipca.R`; o [guia de dados do projeto](projects/data/README.md) descreve os três arquivos e suas fontes. Os notebooks de exploração dos brutos estão sem saídas salvas nesta versão; execute as células para ver os registros e limpe as saídas antes de fazer commit.

## Notebook da última pesquisa

[notebooks/ultima_pesquisa_focus_brutos.ipynb](notebooks/ultima_pesquisa_focus_brutos.ipynb) usa o kernel R para explorar a última `Data` disponível nos 12 recursos estatísticos. Abre as páginas JSON comprimidas da coleta correspondente, confere seus SHA-256 e contagens contra o SQLite, examina campos/tipos/chaves, compara agregado e Top 5 e trata `DatasReferencia` separadamente. Em **02/11/2026**, a API e o snapshot local terminavam em **23/10/2026**; o notebook recalcula a data quando executado novamente.

[notebooks/brutos_2026-10-23.ipynb](notebooks/brutos_2026-10-23.ipynb) imprime os **1.290 objetos JSON originais** de `Data = 2026-10-23`, separados pelos 12 recursos. Ao ser executado, confere os arquivos brutos com os manifestos antes de imprimi-los. As saídas não são armazenadas no Git.

**Escopo dos “brutos”:** são as respostas originais da API de estatísticas, já agregadas pelo BCB; `numeroRespondentes` é uma contagem, não um identificador, e não há previsões individuais nesse snapshot. O recurso de microdados `ExpectativasMercadoInstituicoes` está [desativado pelo BCB por risco de quebra de confidencialidade](https://dadosabertos.bcb.gov.br/dataset/expectativas-mercado/resource/2231aecd-3dbe-4e1a-bae6-674d3be225a1).

Para abrir a partir da raiz do projeto, após restaurar o ambiente com `Rscript -e 'renv::restore(prompt = FALSE)'` e ter o kernel R do Jupyter instalado:

```sh
jupyter lab notebooks/ultima_pesquisa_focus_brutos.ipynb
```

Execute as células para gerar os resultados. Se o kernel R ainda não aparecer no Jupyter, execute `Rscript -e 'IRkernel::installspec(user = TRUE)'` uma vez. O notebook aceita execução a partir da raiz ou de `notebooks/` e usa `dados/atual.json`, sem baixar nem substituir dados.

## Carga histórica, retomada e atualização

O coletor [R/carga_historica.R](R/carga_historica.R) lê novamente o catálogo e o esquema OData, divide os recursos volumosos em meses e os demais em anos, usa páginas de 4.000 linhas, salva cada resposta bruta e confirma sua importação com um registro transacional no SQLite. Cada janela tem manifesto próprio. A checagem de espaço ocorre antes de cada página, com reserva mínima de 5 GiB mais duas vezes a estimativa restante do piloto. A validação e publicação da versão acontecem apenas depois de todas as janelas concluírem.

Na raiz do projeto, após `renv::restore(prompt = FALSE)`:

```sh
# Nova carga integral (necessária em um clone sem banco local)
Rscript R/carga_historica.R iniciar

# Retomar uma coleta interrompida, usando o ID exibido no início da execução
Rscript R/carga_historica.R retomar 20261029T202937Z

# Atualizar com sobreposição: escolha uma data anterior à última observação
Rscript R/carga_historica.R atualizar dados/focus-historico-20261029T204913Z.sqlite 2026-10-01
```

Em uma atualização, o script copia o banco de origem, substitui as linhas desde a data escolhida nos 12 recursos estatísticos e recarrega `DatasReferencia` integralmente. Compara o recorte antigo com o novo em `revisoes.csv`; os brutos e o banco anteriores não são alterados. Se uma janela incompleta mudar na API durante a pausa, a retomada para com os brutos preservados; inicie nova coleta para obter um snapshot consistente. O arquivo `dados/atual.json` só muda após [R/validar_historico.R](R/validar_historico.R) passar em todas as verificações.

### Consultar uma série temporal

O exemplo [analises/serie_ipca_2027.R](analises/serie_ipca_2027.R) lê o snapshot atual e declara recurso, indicador, estatística, período projetado e `baseCalculo`. Execute com `Rscript analises/serie_ipca_2027.R`. A consulta equivalente em R é:

```r
versao <- jsonlite::fromJSON("dados/atual.json")
con <- DBI::dbConnect(RSQLite::SQLite(), versao$banco)
serie <- DBI::dbGetQuery(con, "
  SELECT Data, Mediana, DataReferencia, baseCalculo, coleta
  FROM ExpectativasMercadoAnuais
  WHERE Indicador = ? AND IndicadorDetalhe IS NULL
    AND DataReferencia = ? AND baseCalculo = ?
  ORDER BY Data", params = list("IPCA", "2027", 0L))
DBI::dbDisconnect(con)
```

`Data` é a data em que a expectativa foi observada; `DataReferencia` é o ano projetado. O `coleta` em cada linha informa qual extração forneceu aquele ponto dentro do snapshot lógico `versao$coleta`. No snapshot atual, esta série tem **951 pontos**, de **10/01/2023** a **23/10/2026**; a última mediana original é **4,3368**.

### Gráficos de exemplo

Execute `Rscript analises/graficos_exemplo.R` para gerar novamente os três PNGs a partir de `dados/atual.json`. Os filtros e a leitura de cada visual estão em [analises/graficos/README.md](analises/graficos/README.md): [IPCA por ano projetado](analises/graficos/ipca_anos_alvo.png), [Selic 2027 por base de cálculo](analises/graficos/selic_2027_bases.png) e [IPCA de 12 meses com e sem suavização](analises/graficos/ipca_12m_suavizacao.png).

## Piloto preservado

A amostra dos 12 recursos estatísticos cobre `Data` de **16 a 23/10/2026** (seis dias úteis). O recurso `DatasReferencia` não tem coluna `Data`; foi testado com `DataReferencia1` de **1 a 23/10/2026**.

Fonte: [catálogo oficial do BCB](https://dadosabertos.bcb.gov.br/dataset/expectativas-mercado), [metadados OData](https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/$metadata) e [histórico de alterações](https://www.bcb.gov.br/conteudo/dadosabertos/BCBDeinf/historicos_alteracoes_api_conjuntos_dados_abertos/historico_alteracoes_expectativas.csv). O recurso por instituição está marcado como desativado no catálogo e foi excluído.

## Resultado da coleta `20261029T193528Z`

| Recurso OData | Grupo | Linhas | Páginas |
| --- | --- | ---: | ---: |
| `ExpectativaMercadoMensais` | agregado mensal | 2.520 | 6 |
| `ExpectativasMercadoSelic` | agregado Selic | 192 | 1 |
| `ExpectativasMercadoTrimestrais` | agregado trimestral | 840 | 2 |
| `ExpectativasMercadoAnuais` | agregado anual | 1.920 | 4 |
| `ExpectativasMercadoInflacao12Meses` | agregado inflação 12 meses | 168 | 1 |
| `ExpectativasMercadoInflacao24Meses` | agregado inflação 13 a 24 meses | 144 | 1 |
| `ExpectativasMercadoTop5Mensais` | Top 5 mensal | 954 | 2 |
| `ExpectativasMercadoTop5Selic` | Top 5 Selic | 192 | 1 |
| `ExpectativaMercadoTop5Trimestral` | Top 5 trimestral | 408 | 1 |
| `ExpectativasMercadoTop5Anuais` | Top 5 anual | 330 | 1 |
| `ExpectativasMercadoTop5Inflacao12Meses` | Top 5 inflação 12 meses | 36 | 1 |
| `ExpectativasMercadoTop5Inflacao24Meses` | Top 5 inflação 13 a 24 meses | 36 | 1 |
| `DatasReferencia` | referências Top 5 | 5 | 1 |
| **Total** | | **7.745** | **23** |

O inventário (`dados/manifestos/20261029T193528Z/inventario.json`) guarda nome e descrição do catálogo, endpoint exato, campos e tipos OData, chave candidata e primeira/última data retornada pela API. Os esquemas dos 13 recursos são tratados separadamente. As tabelas SQLite têm todas as colunas nativas, mais `recurso` e `coleta`; não há visão analítica ou índice da futura carga histórica.

## Validação

- Os manifestos por recurso (`dados/manifestos/20261029T193528Z`) registram URL codificada, filtro, página, horários, contagem, tamanho e SHA-256 do arquivo compactado. As 23 páginas foram recebidas e interpretadas como JSON. Uma consulta adicional com `$skip` igual à contagem baixada retornou zero linha nos 13 recursos (paginacao.csv (`dados/manifestos/20261029T193528Z/paginacao.csv`)).
- As 7.745 linhas do SQLite coincidem com os manifestos. Não houve grupos de chaves candidatas duplicados, datas inválidas, tipo numérico inválido ou valor numérico ausente na amostra (validacoes.csv (`dados/manifestos/20261029T193528Z/validacoes.csv`)). As chaves incluem `baseCalculo`, `tipoCalculo`, `Suavizada`, `IndicadorDetalhe` e `Reuniao` quando presentes; seus valores distintos permaneceram separados.
- A cobertura por recurso e indicador (`dados/manifestos/20261029T193528Z/cobertura.csv`) tem 78 pares. Não houve lacuna em dias úteis entre a primeira e a última data observada em cada par desta amostra. Uma lacuna futura não deve ser preenchida com zero: o catálogo informa que períodos sem estatísticas são omitidos.
- [R/verificar.R](R/verificar.R) reabriu todos os arquivos brutos, conferiu SHA-256 e contagens e reconstruiu as 13 tabelas em um banco temporário; os registros reconstruídos coincidiram com o banco entregue.
- Dez verificações de medianas e número de respondentes em duas datas, indicadores e horizontes foram iguais aos relatórios oficiais [16/10](https://www.bcb.gov.br/content/focus/focusmarketreadout/R20261016.pdf) e [23/10/2026](https://www.bcb.gov.br/content/focus/focusmarketreadout/R20261023.pdf), após arredondar a mediana da API a duas casas (comparacao_focus.csv (`dados/manifestos/20261029T193528Z/comparacao_focus.csv`)). A comparação usa `baseCalculo = 0` para a coluna agregada do PDF e `Suavizada = S` para inflação suavizada de 12 meses. Os PDFs foram guardados junto aos manifestos.

## Espaço

Medições em bytes e estimativa detalhada: espaco.json (`dados/manifestos/20261029T193528Z/espaco.json`), estimativa_espaco.csv (`dados/manifestos/20261029T193528Z/estimativa_espaco.csv`) e verificacao_reconstrucao.json (`dados/manifestos/20261029T193528Z/verificacao_reconstrucao.json`).

| Item | Tamanho |
| --- | ---: |
| 23 JSON brutos comprimidos | 135.964 bytes (0,130 MiB) |
| Banco SQLite piloto | 1.130.496 bytes (1,078 MiB) |
| Diretório temporário do R, pico de arquivos observado | 0 bytes |
| Arquivo auxiliar de transação SQLite, pico observado | 12.824 bytes |
| Banco temporário usado na prova de reconstrução, depois removido | 1.130.496 bytes (1,078 MiB) |
| Espaço livre no volume ao fim da coleta | 64.010.547.200 bytes (59,61 GiB) |
| Espaço livre após instalar e validar o ambiente, às 19:42 UTC | 63.873.404.928 bytes (59,49 GiB) |
| Histórico bruto estimado | 145.687.511 bytes (139 MiB) |
| SQLite histórico estimado | 1.211.343.799 bytes (1,13 GiB) |
| **Brutos + SQLite históricos estimados** | **1.357.031.310 bytes (1,26 GiB; 2,12% do livre)** |

A estimativa extrapola, por recurso, os bytes comprimidos por dia útil do piloto ao intervalo entre a primeira e a última observação da API; para `DatasReferencia`, usa dias corridos. O tamanho do SQLite é projetado pela razão observada entre banco e brutos. É uma **ordem de grandeza**, pois volume de indicadores, cobertura, compressão, revisões e índices podem variar no histórico. O diretório temporário do R e o auxiliar SQLite foram medidos durante a importação em páginas de 500 linhas; a reconstrução de validação criou outro banco temporário do tamanho do banco piloto. Essas medições não representam o pico de uma futura criação de índices ou reconstrução integral. Como margem operacional ilustrativa, brutos mais **três vezes** o SQLite estimado somam cerca de **3,52 GiB**, ainda abaixo dos **59,49 GiB** livres na verificação final; isso não é garantia de espaço para uma carga integral.

## Problemas e limites observados

- Nesta API, o parâmetro OData precisa aparecer como `%24filter` na URL. Uma chamada com `$filter` literal retornou HTTP 400; uma chamada com o nome do parâmetro omitido retornou dados sem filtro. O coletor codifica todos os nomes e valores.
- `/$count` retornou HTTP 403 e `$count=true` não trouxe `@odata.count`. Assim, não há contagem independente fornecida pelo serviço; a validação de completude usa páginas de 500, última página menor e a consulta seguinte vazia.
- O recurso `DatasReferencia` tem `DataReferencia1`/`DataReferencia2`, sem `Data`; sua última data no inventário é **04/12/2026**, uma data de referência futura em relação à coleta, não uma observação estatística futura.
- O piloto verifica chaves **candidatas** na amostra. Antes da carga integral, elas e as estimativas de espaço precisam ser reavaliadas com janelas históricas de épocas diferentes. Não foram criadas rotinas de retomada ou atualização da carga histórica nesta etapa.

## Repetir o piloto

Use R 4.6.1 ou compatível, com acesso HTTPS ao BCB e ao CRAN. Na raiz desta pasta:

```sh
Rscript -e 'install.packages("renv", repos="https://cloud.r-project.org")'
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript R/piloto.R
Rscript R/verificar.R
Rscript R/verificar_paginacao.R
Rscript R/validar_focus.R
```

O `renv.lock` fixa as versões usadas; `.Rprofile` ativa a biblioteca do projeto. Cada execução cria um identificador UTC novo, seus JSON em `dados/bruto/<coleta>/<recurso>/`, os manifestos em `dados/manifestos/<coleta>/` e um banco `dados/focus-piloto-<coleta>.sqlite`, sem sobrescrever outra coleta. Os três verificadores usam a coleta mais recente se não receberem um identificador como argumento. `validar_focus.R` baixa e guarda os dois PDFs oficiais se ainda não estiverem presentes e é específico da janela padrão. Para outra janela curta, defina `FOCUS_INICIO`, `FOCUS_FIM` e, opcionalmente, `FOCUS_PAGINA` (até 1.000); depois execute os verificadores de reconstrução e paginação. A janela de `DatasReferencia` começa no primeiro dia do mês de `FOCUS_INICIO` e termina em `FOCUS_FIM`.

Em um sandbox que bloqueie a pasta de cache do usuário, prefixe os comandos `Rscript` com `RENV_PATHS_ROOT=/private/tmp/focus-renv RENV_CONFIG_SANDBOX_ENABLED=FALSE`. Fora desse ambiente restrito, use os comandos acima.

Exemplo de consulta seletiva no banco entregue:

```r
con <- DBI::dbConnect(RSQLite::SQLite(), "dados/focus-piloto-20261029T193528Z.sqlite")
DBI::dbGetQuery(con, "SELECT Data, DataReferencia, Mediana, baseCalculo FROM ExpectativasMercadoAnuais WHERE Indicador = 'IPCA' AND DataReferencia = '2027' AND baseCalculo = 0 ORDER BY Data")
DBI::dbDisconnect(con)
```

Toda a pasta `dados/` está no `.gitignore`; código, `renv.lock`, o relatório e este README são versionados.
