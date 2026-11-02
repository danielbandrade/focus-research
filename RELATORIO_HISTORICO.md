# Carga histórica do Focus — 29/10/2026

Os arquivos citados em `dados/` pertencem à coleta local e não são publicados no repositório Git.

## Estado

A carga inicial `20261029T202937Z` cobriu os **13 recursos ativos** do [catálogo do BCB](https://dadosabertos.bcb.gov.br/dataset/expectativas-mercado), desde a primeira até a última data informada pela API em cada recurso. Foram concluídas **1.396 janelas**, **1.980 páginas** e **4.959.428 linhas**. O intervalo estatístico mais antigo começa em **30/04/1999** e termina em **23/10/2026**. `DatasReferencia` vai de **07/11/2001** a **04/12/2026**; esta última é uma data de referência, não uma observação de expectativa futura.

| Recurso | Linhas | Páginas | Indicadores |
| --- | ---: | ---: | ---: |
| `ExpectativaMercadoMensais` | 1.399.510 | 494 | 17 |
| `ExpectativasMercadoSelic` | 89.270 | 32 | 1 |
| `ExpectativasMercadoTrimestrais` | 295.604 | 300 | 12 |
| `ExpectativasMercadoAnuais` | 1.067.533 | 398 | 33 |
| `ExpectativasMercadoInflacao12Meses` | 117.857 | 48 | 13 |
| `ExpectativasMercadoInflacao24Meses` | 31.173 | 11 | 6 |
| `ExpectativasMercadoTop5Mensais` | 1.184.353 | 457 | 7 |
| `ExpectativasMercadoTop5Selic` | 181.206 | 60 | 1 |
| `ExpectativaMercadoTop5Trimestral` | 81.570 | 24 | 5 |
| `ExpectativasMercadoTop5Anuais` | 420.813 | 115 | 8 |
| `ExpectativasMercadoTop5Inflacao12Meses` | 78.561 | 34 | 4 |
| `ExpectativasMercadoTop5Inflacao24Meses` | 10.855 | 6 | 2 |
| `DatasReferencia` | 1.123 | 1 | 11 |

O snapshot inicial está em `dados/focus-historico-20261029T202937Z.sqlite`. Os brutos da carga (`dados/bruto/20261029T202937Z`) são JSON comprimidos por página e janela; os manifestos (`dados/manifestos/20261029T202937Z`) guardam filtros, URLs, horários, contagens, esquema e SHA-256. Catálogo, metadados OData e histórico de alterações foram copiados no início. O recurso de instituições desativado foi excluído.

## Retomada e atualização verificadas

A execução inicial foi pausada deliberadamente depois de duas páginas confirmadas. `retomar` reconheceu os arquivos, conferiu o hash da última página contra a API e continuou sem duplicar linhas. A página e o registro de ingestão são confirmados na mesma transação SQLite; um bruto salvo antes dessa transação é reutilizado na retomada.

Uma atualização de teste com sobreposição desde **16/10/2026** criou o snapshot `20261029T204913Z`, agora indicado em `dados/atual.json`. Ela recarregou **8.863 linhas** e o recurso completo de datas de referência, conservando **4.959.428 linhas** no banco. A comparação de revisões (`dados/manifestos/20261029T204913Z/revisoes.csv`) registrou **zero registros adicionados, removidos ou revisados** nos 13 recursos. O snapshot inicial e seus brutos permaneceram intactos. O banco atual está em `dados/focus-historico-20261029T204913Z.sqlite`.

## Validações

- Todos os manifestos de janela estão completos. Cada bruto foi reaberto, descompactado e conferido por SHA-256, tamanho, número de linhas, colunas e limites da janela; os totais batem com o registro transacional e o SQLite.
- `PRAGMA integrity_check` retornou `ok`. Há **zero grupos de chaves duplicadas**, **zero datas inválidas** e **zero tipos numéricos inválidos**. Índices foram criados para chave, série e data onde aplicável (`dados/manifestos/20261029T204913Z/validacoes_historicas.csv`).
- As 10 comparações (`dados/manifestos/20261029T204913Z/comparacao_focus.csv`) de medianas e respondentes com os relatórios Focus oficiais de [16/10](https://www.bcb.gov.br/content/focus/focusmarketreadout/R20261016.pdf) e [23/10/2026](https://www.bcb.gov.br/content/focus/focusmarketreadout/R20261023.pdf) passaram, com arredondamento das medianas da API a duas casas.
- A cobertura por recurso e indicador (`dados/manifestos/20261029T204913Z/cobertura_historica.csv`) contém **120 pares**, com primeira/última data, linhas, datas distintas, lacunas de dias úteis e horário da última extração. **109 pares** têm ao menos uma lacuna de dia útil no intervalo. Feriados e períodos sem estatísticas são possíveis; lacunas não foram preenchidas nem tratadas automaticamente como erro.
- Há **2.858.163 ocorrências de valor numérico ausente somadas entre campos**, detalhadas em `dados/manifestos/20261029T204913Z/ausentes_historicos.csv`. A maior parte envolve `numeroRespondentes` e medidas de dispersão/extremos em dados antigos de Top 5. Esse total conta campos ausentes, não linhas distintas; nenhum `NULL` foi convertido em zero.

## Espaço

O bruto comprimido da carga inicial ocupa **46.548.384 bytes (44,39 MiB)**. O SQLite com índices ocupa **1.113.460.736 bytes (1,04 GiB)** por snapshot. A atualização recente acrescentou **139.985 bytes** de brutos e outro banco versionado do mesmo tamanho. Na checagem final havia cerca de **57,24 GiB** livres.

O log de espaço da carga (`dados/manifestos/20261029T202937Z/espaco_durante.csv`) contém **1.983 verificações** antes e durante as páginas; o menor valor livre registrado foi **63.084.269.568 bytes**, contra exigência máxima de **8.082.591.517 bytes**. A atualização (`dados/manifestos/20261029T204913Z/espaco_durante.csv`) teve mais 14 verificações, com mínimo livre de **61.457.412.096 bytes**. O coletor interrompe antes de uma página se o espaço cair abaixo de 5 GiB mais duas vezes a estimativa restante. A estimativa vem do piloto e pode errar; a reserva fixa permanece mesmo depois de excedida.

## Limites

A API não forneceu uma contagem independente (`/$count` respondeu 403 no piloto). O fechamento das janelas usa paginação ordenada até uma resposta menor que 4.000 linhas, inclusive uma página vazia quando o total é múltiplo exato. O snapshot registra instantes de extração por página: não implica que todas as respostas do BCB foram produzidas simultaneamente. Se a última página de uma janela incompleta mudar entre uma interrupção e a retomada, o coletor para e preserva o material anterior. Os manifestos e brutos históricos devem ser mantidos para reconstruir ou auditar versões atualizadas.
