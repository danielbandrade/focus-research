# Proposta de projeto — Simulação conjunta das expectativas de inflação para 2027

**Disciplina:** Simulation of Complex Systems I  
**Prazo do relatório final:** 18/12/2026  
**Base congelada para a proposta:** snapshot Focus `20261029T204913Z`, com observações até 23/10/2026.

## 1. Pergunta de pesquisa

**Até o prazo do projeto, qual é a probabilidade simulada de as medianas das expectativas para IPCA, IPCA Livres e IPCA Administrados de 2027 subirem simultaneamente pelo menos 0,10 ponto percentual em relação a 23/10/2026? Quanto essa probabilidade muda quando preservamos a associação histórica entre as revisões das três séries, em comparação com uma simulação que as amostra separadamente?**

O evento conjunto é definido antes da simulação: as três medianas em 18/12/2026 devem ser pelo menos 0,10 p.p. maiores que seus valores iniciais. A comparação mede a importância da dependência observada nas *expectativas publicadas*; não pretende prever a inflação efetiva de 2027 nem identificar efeitos causais entre componentes.

## 2. Por que simulação?

As três expectativas variam em conjunto e passam muitos dias sem mudança. A probabilidade de um evento simultâneo ao fim de várias revisões não é bem representada pelo produto de três probabilidades individuais quando há associação entre as séries. A simulação de Monte Carlo permite gerar trajetórias alternativas a partir das revisões históricas, preservar sua dependência temporal e transversal e comparar o resultado com um cenário de independência construído sobre os mesmos dados marginais.

O recorte preliminar já mostra associação nas **mudanças diárias das medianas**: correlação de Pearson de **0,518** entre IPCA e IPCA Livres, **0,478** entre IPCA e IPCA Administrados e **0,526** entre IPCA Livres e IPCA Administrados. Essas correlações motivam o experimento; não são resultados da simulação.

## 3. Métodos propostos

1. **Seleção e caracterização.** Consultar `ExpectativasMercadoAnuais` com `Indicador` em `IPCA`, `IPCA Livres` e `IPCA Administrados`, `IndicadorDetalhe IS NULL`, `DataReferencia = '2027'`, `baseCalculo = 0` e `Data` entre 02/01/2025 e 23/10/2026. Alinhar as séries por `Data`, conferir ausências e calcular as diferenças entre medianas consecutivas em p.p. Descrever níveis, mudanças, proporção de dias sem revisão e correlações.
2. **Cenário conjunto.** Aplicar *moving block bootstrap* aos vetores diários das três diferenças, sorteando blocos de cinco observações consecutivas com reposição. Somar os blocos à última mediana observada até completar o horizonte simulado. O mesmo bloco é usado para as três variáveis em cada sorteio, preservando co-movimentos e parte da persistência temporal.
3. **Cenário independente.** Repetir o procedimento sorteando blocos separadamente para cada indicador. Cada série conserva sua distribuição empírica e sua dinâmica dentro do bloco; a associação entre indicadores é removida na construção das trajetórias.
4. **Experimento e comparação.** Gerar **20.000 trajetórias por cenário**, com semente registrada em R. O horizonte será o número de dias de observação da API entre 23/10 e 18/12/2026; **40 dias de segunda a sexta** são apenas a aproximação inicial, a ajustar pelos feriados e pelo calendário efetivo da série. Estimar a frequência do evento conjunto, sua diferença absoluta entre cenários e a razão entre as probabilidades, quando o denominador for positivo.
5. **Diagnóstico e incerteza.** Verificar estabilização das estimativas em 1.000, 5.000, 10.000 e 20.000 trajetórias. Informar erro padrão de Monte Carlo para cada probabilidade, separado da incerteza do modelo. Repetir a análise com blocos de 3 e 10 observações e com calibração restrita a 2026; reportar como essas escolhas mudam o resultado. Usar os limiares de 0,05 e 0,20 p.p. como análises de sensibilidade.

**Regra de interpretação:** as medianas de IPCA, Livres e Administrados são agregados estatísticos de respostas possivelmente diferentes. Não será imposta uma identidade contábil entre elas nem serão simuladas previsões individuais, que não estão disponíveis nessa base.

## 4. Dados e parâmetros

O [relatório histórico](../RELATORIO_HISTORICO.md) documenta **4.959.428 linhas** dos 13 recursos ativos, com validação do SQLite e comparações com relatórios oficiais do BCB. Para esta proposta, o recorte de três indicadores tem **455 datas comuns** de 02/01/2025 a 23/10/2026, portanto **454 vetores de mudanças consecutivas**; não há mediana ausente nesse recorte. `Data` é a data da expectativa, enquanto `DataReferencia = 2027` identifica o ano projetado.

| Indicador (`Mediana`, `baseCalculo = 0`) | 23/10/2026 | Limiar do evento (alta ≥ 0,10 p.p.) |
| --- | ---: | ---: |
| IPCA 2027 | 4,3368% | 4,4368% |
| IPCA Livres 2027 | 4,5202% | 4,6202% |
| IPCA Administrados 2027 | 3,9896% | 4,0896% |

Os valores vêm do snapshot indicado em [`dados/atual.json`](../dados/atual.json), consultado nesta proposta. Os arquivos em `dados/` são locais e ignorados pelo Git; em outra máquina será preciso reconstruir o snapshot seguindo o [README](../README.md). O projeto usará R com as dependências fixadas em `renv.lock` e manterá o identificador do snapshot, filtros, semente e parâmetros no material suplementar.

## 5. Resultados esperados

- Tabela descritiva das três séries e gráfico de suas medianas e revisões ao longo do tempo.
- Distribuições simuladas das medianas em 18/12/2026 e gráfico da probabilidade do evento conjunto nos dois cenários.
- Estimativa de **quanto a probabilidade muda entre os dois cenários de dependência** das revisões, acompanhada do erro de Monte Carlo e das análises de sensibilidade.
- Gráfico de convergência e discussão sobre dependência histórica, janela de calibração, dias sem revisão, feriados e impossibilidade de inferir previsões individuais ou inflação realizada.

Não há resultado numérico antecipado para a probabilidade: o sinal e o tamanho da diferença serão determinados pela simulação. Se o evento for muito raro, serão apresentados também os limiares alternativos previstos acima, sem substituir silenciosamente o evento principal.

## 6. Cronograma — semanas 13 a 15

| Semana | Marco e entrega |
| --- | --- |
| **13** | Congelar o snapshot; extrair e validar as três séries; produzir estatísticas descritivas; fechar horizonte e evento principal. |
| **14** | Implementar os dois simuladores em R; executar 20.000 trajetórias por cenário; conferir reprodução com semente e diagnóstico de convergência. |
| **15** | Fazer sensibilidades, interpretar os resultados e redigir o artigo de **6–8 páginas**; revisar figuras, código e referências; entregar até **18/12/2026**. |

## Estrutura prevista do relatório final

1. **Resumo:** pergunta, método, probabilidades encontradas e conclusão.
2. **Introdução:** motivação e hipótese de que a dependência altera a frequência do evento conjunto.
3. **Métodos:** origem e filtros dos dados, caracterização das três variáveis numéricas, algoritmo, parâmetros e definição dos cenários.
4. **Resultados:** trajetórias, probabilidades, convergência, erro de Monte Carlo e sensibilidades.
5. **Discussão:** interpretação, limites do bootstrap histórico e possíveis extensões.
6. **Referências:** [catálogo de expectativas do BCB](https://dadosabertos.bcb.gov.br/dataset/expectativas-mercado), [relatório histórico local](../RELATORIO_HISTORICO.md) e referências metodológicas utilizadas na implementação.
7. **Apêndice ou suplemento:** código R essencial, instruções de reprodução e declaração de como ferramentas de IA foram utilizadas na preparação do trabalho.
