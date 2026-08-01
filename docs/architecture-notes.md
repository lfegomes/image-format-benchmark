# Notas de arquitetura e decisões de implementação

Este documento explica **por que** o código deste repositório foi
estruturado da forma como está. Para entender **o que** o software faz e como cada cálculo ocorre, veja
[docs/how-it-works.md](how-it-works.md). Para instruções de uso, veja o
[README.md](../README.md) principal e o README de cada subprojeto.

## Três produtos independentes

O repositório contém três programas que não compartilham código entre
si, apenas um contrato de dados (`manifest.json`) e um layout de
diretórios combinado:

1. **`dataset/`** — pacote Dart autônomo que seleciona as imagens de
   entrada (quantidade configurável via `--count`) e gera as variantes
   (12 por imagem) + manifesto.
2. **`image_analysis_server/`** — servidor HTTP estático em
   Node.js/TypeScript, que apenas serve os arquivos já preparados.
3. **`image_analysis_app/`** — o aplicativo Flutter que descobre as
   variantes pelo manifesto, executa as tarefas de medição e persiste os
   resultados.

Essa separação existe porque o objeto de estudo é o **carregamento no
Flutter**, não a infraestrutura de apoio. Isolar o servidor como um
processo Node.js à parte (em vez de, por exemplo, embuti-lo no próprio
app ou reaproveitar algum framework) manteve o comportamento do servidor
mínimo, fixo e fácil de auditar (arquivos estáticos, sem transformação de
imagem, sem cache) — o app continua sendo o único responsável por
controlar requisições, medir download e decodificação, calcular SSIM e
persistir resultados. A escolha de Node.js/TypeScript especificamente
(em vez de, por exemplo, um servidor Dart) foi por familiaridade prévia
com a stack, para reduzir risco de implementação num componente que é só
infraestrutura de apoio.

## Descoberta por manifesto, não por URLs fixas

Nenhum dos endereços do manifesto está escrito no código do app. O app
recebe apenas a URL-base digitada na tela de configuração, baixa
`manifest.json` a partir dela e resolve cada variante com `Uri.resolve`
(`network/image_downloader.dart`, função `resolveSafeUri`), rejeitando
caminhos absolutos ou com `..` antes de resolver. Isso significa que
trocar o IP do computador, a porta, ou até regenerar o dataset com um
número diferente de imagens não exige recompilar o app — só um novo
`manifest.json` compatível com o schema esperado (validado em
`data/manifest_loader.dart`: contagens batendo, IDs únicos, formatos e
qualidades permitidos, 12 variantes por imagem, caminhos seguros).

## Pipeline de uma tarefa

Cada uma das `N` variantes e tarefas por dispositivo
segue a mesma sequência, implementada em
`benchmark/runner/benchmark_runner.dart`:

1. gerar um `runId` único e montar a URL com esse parâmetro (evita que
   qualquer camada de cache no meio do caminho trate duas tentativas como
   a mesma requisição);
2. cronometrar o download com `HttpClient` (nunca `Image.network`, que
   esconde o pipeline de rede/decodificação atrás de uma API só de
   widget) até receber todos os bytes;
3. cronometrar a decodificação com `ui.instantiateImageCodec` +
   `codec.getNextFrame()` até o primeiro frame pronto, sem
   `cacheWidth`/`cacheHeight` (que fariam o próprio Flutter redimensionar
   a imagem, alterando o que está sendo medido);
4. validar dimensões contra o manifesto e calcular a memória estimada;
5. calcular (ou reaproveitar, se já calculado para esse `variantId` neste
   dispositivo) o SSIM contra a referência normalizada, fora dos dois
   cronômetros acima;
6. persistir a linha no CSV imediatamente — não ao final da rodada — e
   liberar `codec`/`ui.Image`.

As tarefas são executadas **sequencialmente**, nunca em paralelo:
concorrência tornaria os tempos de download menos comparáveis entre
tarefas (disputando a mesma rede/CPU). A ordem das `n` tarefas é
embaralhada com uma semente fixa e registrada
(`buildShuffledTasks`, em `benchmark_runner.dart`), e só depois do
embaralhamento cada tarefa recebe um `sequenceIndex` determinístico —
isso evita que efeitos de aquecimento de rede, JIT ou térmicos do
aparelho fiquem concentrados numa condição específica.

## Estatísticas da tela final (não entra no .csv)

### Amostragem: a imagem é a unidade, não a repetição

As três repetições de uma variante não são tratadas como três
observações independentes na agregação (`benchmark/stats/`): o valor
usado por imagem e condição é a **mediana das três repetições**, e cada
imagem do dataset é uma unidade amostral. Uma condição só entra na
agregação se tiver as três repetições válidas para aquela imagem — caso
contrário, a imagem é excluída dessa condição específica, nunca agregada
com a mediana de 2 (ou 1) repetições em silêncio (o CSV bruto continua
guardando todas as linhas, inclusive erros).

### Fronteira de Pareto

`benchmark/stats/pareto_frontier.dart` implementa a noção mais simples
possível de dominância entre duas métricas: uma condição é dominada
quando existe outra condição igual ou melhor nas duas métricas e
estritamente melhor em pelo menos uma. Para bytes × SSIM, "melhor"
significa menor `received_size_bytes` e maior `ssim`. Deliberadamente não
há pesos arbitrários combinando as métricas numa nota única — isso
esconderia trade-offs que fazem parte do resultado da pesquisa.

## Testes automatizados

Os testes em `image_analysis_app/test/`, `image_analysis_server/test/` e
`dataset/test/` cobrem principalmente as partes onde um erro silencioso
comprometeria os dados, não a interface: estatística descritiva (média,
mediana, desvio-padrão, redução percentual), SSIM (imagem idêntica ≈ 1,
imagens diferentes < 1, validação de faixa), fronteira de Pareto com
dados sintéticos, serialização e validação do manifesto, resolução segura
de URLs/caminhos (o servidor rejeitando `..`, caminhos absolutos e bytes
nulos), serialização do CSV, geração das 12 variantes por imagem no
preparador, e cabeçalhos sem cache no servidor. Testes de integração
completos (app conversando com o servidor de verdade, decodificação de
uma imagem real) são mais caros de manter e cobrem uma fração menor do
risco de dado incorreto, por isso ficam como cobertura secundária.
