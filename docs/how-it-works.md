# Como o software funciona

Referência técnica completa dos três programas deste repositório: o que
cada um faz, exatamente como cada cálculo é feito, quais dados são
produzidos e onde cada coisa está implementada. Para "como rodar" e "como operar o app", veja
o [README.md](../README.md); para "por que a arquitetura é assim", veja
[docs/architecture-notes.md](architecture-notes.md).

## Visão geral do fluxo de dados

```text
dataset/input/*.png (imagens candidatas)
        │
        │  select_images.dart
        │
        ▼
dataset/generated/source/image_NNN.png (N imagens selecionadas)
        │
        │  prepare_dataset.dart
        │
        ▼
dataset/generated/
  manifest.json
  references/image_NNN__reference1080.png
  variants/image_NNN__{original|target1080}__{jpeg|webp}__q{70|85|95}.{jpg|webp}
        │
        │  image_analysis_server (serve estático, sem transformar nada)
        │
        ▼
http://<ip>:<porta>/{health,manifest.json,references/*,variants/*}
        │
        │  image_analysis_app (baixa, decodifica, mede, calcula SSIM)
        │
        ▼
<documents>/exp-<timestamp>.csv (uma linha por tarefa, gravada incrementalmente)
```

## 1. Preparador de dataset (`dataset/`)

Pacote Dart autônomo com dois executáveis, `bin/select_images.dart` e
`bin/prepare_dataset.dart`, que roda antes de qualquer coleta e não é
cronometrado como parte do experimento.

### 1.1 `select_images.dart` — seleção das imagens de entrada

Lê todos os arquivos `.png` de `input/`, ordena pelo nome do arquivo
(`String.compareTo`) e toma os `--count` primeiros (padrão 30). Para cada
arquivo selecionado, na ordem ordenada:

- copia para `generated/source/image_NNN.png`, onde `NNN` é o índice
  1-based com zero-padding de 3 dígitos (`image_001.png`,
  `image_002.png`, ...);
- registra em `generated/selected_images.txt` (formato CSV simples com
  comentários `#`) a regra usada e o par `imageId,originalFilename`.

Nenhuma imagem é escolhida manualmente — a ordem de entrada em `input/`
não importa, só o nome do arquivo. Flag: `--count`.

### 1.2 `prepare_dataset.dart` — geração das variantes e do manifesto

Para cada imagem em `generated/source/` (já ordenadas por nome), na função
`generateManifest`:

1. Decodifica o PNG (`img.decodePng`) e verifica que o lado maior é
   estritamente maior que `targetLongestSidePx` (1080px) — lança
   `StateError` caso contrário, porque o perfil `target1080` só faz
   sentido como redução real.
2. Gera a versão redimensionada (`_resizeToLongestSide`): `copyResize`
   com `img.Interpolation.linear`, fixando o lado maior em 1080px e
   preservando a proporção pelo lado menor. **Este mesmo bitmap** é usado
   para duas finalidades: (a) salvo como PNG em
   `references/{imageId}__reference1080.png` — a referência usada depois
   pelo SSIM — e (b) reencodado como as variantes `target1080` em JPEG e
   WebP. Ou seja, a referência de SSIM e o perfil `target1080` sempre
   partem exatamente dos mesmos pixels redimensionados.
3. Para cada uma das duas resoluções (`original` = bitmap decodificado
   sem alteração; `target1080` = bitmap do passo 2) e cada uma das três
   qualidades (`70`, `85`, `95`):
   - **JPEG:** `img.encodeJpg(image, quality: quality)`.
   - **WebP com perdas:** grava um PNG temporário (só quando o perfil é
     `target1080`; o perfil `original` reaproveita o PNG-fonte
     diretamente) e chama o binário `cwebp` via `Process.run` com os
     argumentos `-preset photo -q <quality> <input> -o <output>`; lança
     `StateError` se `exitCode != 0`.
   - Cada arquivo gerado vira uma entrada no manifesto (ver 1.3) com o
     `variantId` `{imageId}__{profile}__{format}__q{quality}`, por
     exemplo `image_001__target1080__webp__q85`.
4. Resultado por imagem: 2 perfis × 2 formatos × 3 qualidades = **12
   variantes**; total de variantes = `12 × quantidade de imagens
   selecionadas` (exemplo: 20 imagens-fonte → 240 variantes; o padrão
   atual do repositório é 30 imagens → 360 variantes).

Falha explícita em qualquer etapa (decodificação, redimensionamento,
`cwebp`) interrompe a geração — nunca produz um manifesto parcial em
silêncio.

### 1.3 `manifest.json`

```json
{
  "schemaVersion": 1,
  "datasetId": "photo-benchmark-v1",
  "generatedAt": "2026-07-23T12:00:00.000Z",
  "sourceImageCount": 20,
  "variantCount": 240,
  "repetitionsPerVariant": 3,
  "resizeAlgorithm": "linear",
  "encoders": { "jpeg": "package:image 4.9.1", "webp": "cwebp 1.6.0 ..." },
  "preparerScriptVersion": "1.0.0",
  "cwebpArgs": "-preset photo -q <quality> <input> -o <output>",
  "variants": [
    {
      "variantId": "image_001__target1080__webp__q85",
      "sourceImageId": "image_001",
      "relativeUrl": "variants/image_001__target1080__webp__q85.webp",
      "referenceUrl": "references/image_001__reference1080.png",
      "format": "webp",
      "quality": 85,
      "resolutionProfile": "target1080",
      "encodedSizeBytes": 123456,
      "width": 1080,
      "height": 720
    }
  ]
}
```

`encoders.jpeg`/`encoders.webp` são preenchidos automaticamente: a versão
do pacote `image` é lida de `pubspec.lock`, e a versão do `cwebp` chamando
`cwebp -version`. `generatedAt` é `DateTime.now().toUtc()`.

## 2. Servidor HTTP (`image_analysis_server/`)

Servidor Node.js/TypeScript sobre `node:http`, sem framework. Serve
exatamente os arquivos gerados no passo anterior, sem transformar nada.

### 2.1 Rotas (`src/server.ts`)

```text
GET|HEAD /health              → { "status": "ok" }, 200
GET|HEAD /manifest.json       → arquivo estático
GET|HEAD /references/<...>    → arquivo estático
GET|HEAD /variants/<...>      → arquivo estático
qualquer outro caminho        → 404
qualquer outro método         → 405, header Allow: GET, HEAD
```

### 2.2 Resolução segura de caminho (`resolveSafePath`, `src/static_file_handler.ts`)

1. Rejeita bytes nulos (`\0`) crus ou depois de `decodeURIComponent`.
2. Rejeita se algum segmento do caminho for `..` ou `.`.
3. Resolve o caminho absoluto com `path.resolve(rootDir, ...segments)` e
   confere com `path.relative(rootDir, candidate)` que o resultado não
   começa com `..` nem é absoluto (ou seja, não escapou de `rootDir`).
4. O próprio diretório raiz nunca é servível (`relative === ''` → `null`).

Caminho inseguro → `403`. Caminho seguro mas arquivo inexistente ou não é
um arquivo regular → `404`. Extensão fora de
`.json/.png/.jpg/.jpeg/.webp` → `415`.

### 2.3 Cabeçalhos (`src/response_headers.ts`)

Toda resposta de arquivo ou de `/health` inclui:

```text
Cache-Control: no-store, no-cache, must-revalidate, max-age=0
Pragma: no-cache
Expires: 0
```

mais `Content-Type` (mapeado pela extensão) e `Content-Length` (tamanho
exato do arquivo). O servidor nunca envia `ETag` nem `Last-Modified` —
não há como o cliente montar `If-None-Match`/`If-Modified-Since`
significativos, então toda resposta bem-sucedida é `200` com o corpo
completo, nunca `304`.

### 2.4 Timeouts de conexão (`createServer`, `src/server.ts`)

`server.keepAliveTimeout = 65000ms` e `server.headersTimeout = 66000ms`
(o padrão do Node é 5000ms). Isso mantém conexões keep-alive vivas por
mais tempo que o `idleTimeout` de 30s configurado no `HttpClient` do app
(`image_analysis_app/lib/benchmark/network/image_downloader.dart`), para
que o cliente sempre descarte uma conexão ociosa antes que o servidor a
feche por baixo dele — evita resets de conexão no meio de uma rodada de
centenas de tarefas sequenciais (ex.: 720, no dataset de 20 imagens
usado na coleta piloto).

### 2.5 Logging (`src/server.ts`)

Cada requisição gera uma linha no console:
`<timestamp ISO> <método> <path> <status> <bytesEnviados>B <duração>ms`.
Diagnóstico apenas — o tempo do servidor não entra na análise principal.

### 2.6 Configuração (`src/server_config.ts`)

CLI: `--root` (padrão `../dataset/generated`), `--host` (padrão
`0.0.0.0`), `--port` (padrão `8080`, precisa ser inteiro positivo).

## 3. Aplicativo Flutter (`image_analysis_app/`)

### 3.1 Modelos de domínio (`lib/benchmark/models/`)

- **`ImageVariant`** — espelha uma entrada do manifesto: `variantId`,
  `sourceImageId`, `relativeUrl`, `referenceUrl`, `format` (enum
  `ImageFormat.jpeg|webp`), `quality` (int), `resolutionProfile` (enum
  `ResolutionProfile.original|target1080`), `manifestSizeBytes`,
  `expectedWidth`, `expectedHeight`.
- **`ExperimentManifest`** — `schemaVersion`, `datasetId`, `generatedAt`,
  `sourceImageCount`, `variantCount`, `repetitionsPerVariant`,
  `resizeAlgorithm`, `encoders`, `variants: List<ImageVariant>`.
- **`BenchmarkTask`** — `variant`, `repetition` (1..3), `sequenceIndex`
  (atribuído após embaralhar, ver 3.5).
- **`BenchmarkResult`** — uma linha do CSV; ver 3.11 para a lista de
  campos. Todo campo de medição é anulável (`int?`/`double?`): fica
  `null` quando a tarefa falha antes daquela etapa terminar, nunca `0`.
- **`DeviceEnvironment`** — `deviceLabel` (`"$model ($operatingSystemVersion)"`),
  `manufacturer`, `model`, `operatingSystemVersion`, `flutterVersion`,
  `dartVersion`.
- **`AggregatedStats`** — `mean`, `median`, `standardDeviation`, `min`,
  `max`, `sampleCount` de uma amostra (ver 3.12 para as fórmulas).

### 3.2 Fluxo de telas

**`SetupScreen`** (`lib/presentation/setup_screen.dart`):

1. Campo de texto para a URL-base (placeholder
   `http://192.168.1.50:8080/`); normalizada para sempre terminar em `/`
   e validada com `Uri.tryParse` (precisa ter `scheme` e `authority`).
2. **"Testar conexão"** — `GET <base>/health` com timeout de 5s; ✓ se
   `200`, senão mostra o motivo (URL inválida, servidor inacessível,
   status inesperado).
3. **"Carregar manifesto"** — `ManifestLoader.fetchAndValidate` (ver 3.3);
   se válido, mostra `"N imagens · M variantes · M×3 tarefas"`.
4. Em paralelo, `collectDeviceEnvironment()` (via `device_info_plus`) e a
   resolução do caminho do CSV: `<ApplicationDocumentsDirectory>/exp-<millisSinceEpoch>.csv`
   (o `experimentId` é literalmente `exp-<DateTime.now().millisecondsSinceEpoch>`).
5. **"Executar experimento"** habilita só quando manifesto, ambiente do
   dispositivo e caminho do CSV estão todos prontos.

**`BenchmarkScreen`** (`lib/presentation/benchmark_screen.dart`):

1. Abre o `CsvExporter` (escreve o cabeçalho se o arquivo for novo).
2. `ReferenceStore.loadAll` — baixa as (até) 20 referências de SSIM (uma
   por `sourceImageId`), fora de qualquer cronômetro de tarefa.
3. Cria o `BenchmarkRunner` com `seed` fixo (`20260724` por padrão,
   parâmetro do widget) e chama `runner.run(progress)`.
4. Enquanto roda, mostra em tempo real (via `ChangeNotifier`): barra de
   progresso (`completedTasks/totalTasks`), variante/repetição/sequência
   atuais, contagem de sucessos/falhas, tempo decorrido.
5. **"Cancelar"** chama `runner.cancel()` — a tarefa em andamento termina
   e é persistida normalmente; nenhuma tarefa nova começa depois disso.
6. Ao terminar (ou cancelar), **"Ver resultados"** navega para a tela de
   resultados com a lista de `BenchmarkResult` acumulada em memória.

**`ResultsScreen`** (`lib/presentation/results_screen.dart`): ver 3.12 e
3.13 para a agregação e a fronteira de Pareto exibidas.

### 3.3 Validação do manifesto (`validateManifest`, `lib/benchmark/data/manifest_loader.dart`)

Todas as regras abaixo lançam `ManifestValidationException` se violadas:

- `variantCount` no JSON precisa ser igual ao tamanho da lista `variants`;
- todo `variantId` precisa ser único;
- `quality` de cada variante precisa estar em `qualityLevels` (`[70, 85, 95]`);
- `relativeUrl` e `referenceUrl` precisam ser caminhos relativos seguros
  (não vazios, não começando com `/`, sem segmento `..`, não sendo uma
  URI absoluta);
- `encodedSizeBytes` (`manifestSizeBytes`) precisa ser `> 0`;
- `width`/`height` precisam ser `> 0`;
- cada `sourceImageId` precisa ter exatamente `variantsPerImage` (12)
  variantes;
- todas as variantes do mesmo `sourceImageId` precisam apontar para o
  mesmo `referenceUrl`.

### 3.4 Resolução segura de URL (`resolveSafeUri`, `lib/benchmark/network/image_downloader.dart`)

Rejeita `relativePath` vazio, começando com `/`, com algum segmento `..`,
ou que não seja parseável/seja absoluto; caso contrário retorna
`baseUri.resolve(relativePath)`. É assim que o app nunca precisa saber os
240 endereços de antemão — só resolve cada um a partir do `relativeUrl`
do manifesto.

### 3.5 Geração e ordenação das tarefas (`buildShuffledTasks`, `lib/benchmark/runner/benchmark_runner.dart`)

```dart
tasks = [para cada variant do manifesto, para repetition em 1..3: BenchmarkTask(variant, repetition)]
tasks.shuffle(Random(seed))
sequenceIndex = índice de cada tarefa na lista já embaralhada (0-based)
```

`tasks.length == manifest.variantCount × 3` (ex.: 240 variantes → 720
tarefas, para um dataset de 20 imagens). A semente
(`seed`, default `20260724` em `BenchmarkScreen`) é fixa e passada
explicitamente, para que a ordem seja reprodutível se necessário —
registre a semente usada em cada rodada real junto aos resultados.

### 3.6 Pipeline de execução de uma tarefa (`BenchmarkRunner`)

Antes da primeira tarefa: **aquecimento** (`_warmUp`) — baixa e decodifica
a variante da primeira tarefa, descarta o resultado. Abre a conexão
TCP/HTTP e aquece o JIT antes de cronometrar qualquer coisa real; falhas
no aquecimento são só logadas, nunca impedem a rodada.

Para cada tarefa, sequencialmente (nunca em paralelo — concorrência
tornaria os tempos de download menos comparáveis entre tarefas),
`_runTaskWithRetries` chama `_runSingleTask` até `maxAttemptsPerTask` (3)
vezes:

1. `runId = "<experimentId>-<sequenceIndex>-a<attempt>"` — novo a cada
   tentativa, garante que cada requisição HTTP seja distinta mesmo em
   retentativas.
2. **Download** (`ImageDownloader.download`, ver 3.7): cronometrado com
   `Stopwatch`.
3. **Decodificação** (`decodeImage`, ver 3.8): cronometrada com outro
   `Stopwatch`, começa só depois do download terminar.
4. Confere que `decodedWidth`/`decodedHeight` batem com
   `variant.expectedWidth`/`expectedHeight` do manifesto; se não baterem,
   descarta a imagem decodificada e registra erro.
5. `decodedMemoryEstimatedBytes = estimatedMemoryBytes(width, height)`
   (ver 3.9), depois `decodeResult.image.dispose()`.
6. **SSIM** (`_ssimFor`, ver 3.10): fora dos dois cronômetros acima.
7. `totalLoadTimeUs = downloadTimeUs + decodeTimeUs`.
8. Monta o `BenchmarkResult` e retorna.

Se qualquer etapa lançar uma exceção antes do passo 8, o resultado da
tentativa é um `BenchmarkResult` de erro: todos os campos de medição
ficam `null`, `error` recebe a mensagem da exceção, `httpStatusCode` fica
preenchido se já havia uma resposta HTTP. Regra de novas tentativas:

- até 3 tentativas por tarefa, cada uma com um `runId` novo (uma
  requisição HTTP de verdade, não reaproveitamento de bytes);
- 500ms de espera (`retryBackoff`) entre tentativas que falharam;
- **só o resultado da última tentativa é persistido** no CSV — não existe
  coluna de "número da tentativa"; tentativas anteriores que falharam
  ficam apenas no log do console.

Depois de cada tarefa (sucesso ou falha definitiva): grava
imediatamente via `resultStore.record` (que já dá `flush` no arquivo) e
espera `intervalBetweenTasks` (250ms) antes da próxima, a menos que o
usuário tenha cancelado.

### 3.7 Download sem cache (`ImageDownloader`, `lib/benchmark/network/image_downloader.dart`)

Usa `HttpClient` puro (nunca `Image.network`, que embutiria o pipeline
inteiro atrás de uma API de widget). Um único `HttpClient` é criado por
rodada (`idleTimeout` de 30s) e reaproveitado em todas as tarefas da
rodada — nada cria ou fecha um `HttpClient` por tarefa.

Para cada tentativa:

1. Resolve a URL segura (3.4) e anexa o parâmetro de query
   `run=<runId>`, único por tentativa — impede que qualquer camada
   intermediária trate duas tentativas como a mesma requisição.
2. `Stopwatch` inicia; `HttpClient.getUrl` com os cabeçalhos
   `Cache-Control: no-cache, no-store, must-revalidate` e
   `Pragma: no-cache`.
3. Lê todos os chunks da resposta (`BytesBuilder`); `Stopwatch` para.
4. Validações, todas lançando `DownloadException` se falharem: status
   HTTP precisa ser `200`; se o header `Content-Length` estiver presente,
   precisa bater com os bytes recebidos; o total de bytes recebidos
   precisa bater com `variant.manifestSizeBytes` do manifesto.

`downloadTimeUs = stopwatch.elapsedMicroseconds` — inclui a requisição e
a leitura completa do corpo, não inclui as validações acima.

### 3.8 Decodificação (`decodeImage`, `lib/benchmark/decoding/image_decoder.dart`)

```dart
stopwatch.start();
codec = await ui.instantiateImageCodec(bytes);
frame = await codec.getNextFrame();
stopwatch.stop();
```

Sem `cacheWidth`/`cacheHeight` (que fariam o próprio Flutter
redimensionar a imagem na decodificação, alterando o que está sendo
medido). `decodeTimeUs = stopwatch.elapsedMicroseconds` — do início da
decodificação até o primeiro frame pronto (`ui.Image`), nunca inclui
renderização na tela.

### 3.9 Memória estimada

```text
decoded_memory_estimated_bytes = decoded_width × decoded_height × 4
```

Matriz RGBA de 32 bits (4 bytes/pixel). É uma estimativa a partir das
dimensões decodificadas, não o consumo real de memória do processo
Flutter (`estimatedMemoryBytes`, `lib/benchmark/decoding/image_decoder.dart`).

### 3.10 SSIM (`lib/benchmark/quality/ssim.dart`)

Cálculo independente da decodificação cronometrada: os bytes da variante
e da referência são decodificados de novo com `package:image`
(`img.decodeImage`), fora dos cronômetros de download/decodificação.

1. Se as dimensões da variante decodificada diferirem das da referência,
   redimensiona a variante para o tamanho da referência com
   `img.copyResize(..., interpolation: Interpolation.linear)` — ajuste
   só para viabilizar a comparação, nunca cronometrado.
2. Converte ambas as imagens para luminância Rec. 601:
   `luminance = 0.299·R + 0.587·G + 0.114·B` por pixel
   (`pixel.luminance` do `package:image`), gerando uma matriz `Float64List`
   por imagem.
3. Percorre a imagem em janelas de `8×8` pixels, não sobrepostas, sem
   ponderação gaussiana. Para cada janela, com `a`/`b` = luminância da
   variante/referência:
   - `meanA`, `meanB` = médias da janela (64 amostras);
   - `varianceA`, `varianceB` = variância populacional da janela (divisor
     64, não 63);
   - `covariance` = covariância populacional entre as duas janelas;
   - `C1 = (0.01×255)²`, `C2 = (0.03×255)²` (constantes de estabilização
     de Wang et al. 2004, para luminância em `[0, 255]`);
   - SSIM da janela =
     `((2·meanA·meanB + C1)·(2·covariance + C2)) / ((meanA² + meanB² + C1)·(varianceA + varianceB + C2))`.
4. O SSIM da variante é a **média aritmética simples do SSIM de todas as
   janelas completas** (janelas parciais na borda são descartadas).
5. **Validação de faixa:** se o resultado for `NaN`, infinito, ou estiver
   fora de `[-1.5, 1.5]`, lança `SsimException` em vez de gravar um valor
   sem sentido no CSV — a margem `[-1.5, 1.5]` (em vez do teórico `[-1, 1]`)
   é só para pegar bugs sem rejeitar casos-limite legítimos.
6. **Cache:** calculado uma única vez por `variantId` (mapa em memória em
   `BenchmarkRunner`), reaproveitado nas repetições seguintes daquela
   mesma variante — o pipeline de decodificação é determinístico, então
   recalcular não mudaria o resultado.

### 3.11 Persistência incremental em CSV (`lib/benchmark/data/csv_exporter.dart`)

Colunas, nesta ordem exata:

```text
experiment_id, run_id, sequence_index, variant_id, source_image_id,
repetition, format, quality, resolution_profile, received_size_bytes,
download_time_us, decode_time_us, total_load_time_us, decoded_width,
decoded_height, decoded_memory_estimated_bytes, ssim, device_label,
flutter_version, operating_system_version, server_base_url,
http_status_code, error, timestamp
```

Campos de medição ausentes (tarefa com erro) viram string vazia, nunca
`0`. `timestamp` é `DateTime.now().toUtc().toIso8601String()`, capturado
no início da tentativa. Escrita: cabeçalho gravado uma única vez (só se o
arquivo ainda não existir ou estiver vazio — permite retomar uma rodada
sem duplicar o cabeçalho); `flush()` no disco depois de cada linha;
campos com vírgula, aspas ou quebra de linha são colocados entre aspas
duplas com `"` duplicado (`escapeCsvField`).

### 3.12 Agregação estatística (`ResultsScreen._aggregatedResults`)

**Estatística descritiva pura** (`lib/benchmark/stats/descriptive_stats.dart`,
sem I/O, usada tanto na tela quanto testável isoladamente):

- `mean`: média aritmética simples.
- `median`: valor central (ou média dos dois centrais, se `n` for par).
- `standardDeviation`: desvio-padrão **amostral** (divisor `n − 1`);
  retorna `0` para amostras com menos de 2 valores.
- `minOf`/`maxOf`: mínimo/máximo.
- `percentageReduction({baseline, comparison})`:
  `(baseline − comparison) / baseline × 100` — positivo significa que
  `comparison` é menor que `baseline`.

**Agregação por condição**, na tela de resultados:

1. Filtra só resultados sem erro (`!isError`).
2. Agrupa por `(sourceImageId, formato, qualidade, resolutionProfile)`.
3. Para cada grupo (uma imagem, uma condição): se **não** tiver
   exatamente `repetitionsPerVariant` (3) repetições bem-sucedidas, a
   imagem é **excluída** dessa condição — nunca agregada com a mediana de
   um conjunto incompleto em silêncio. A contagem de exclusões é somada e
   exibida na tela (em laranja), nunca escondida; o CSV bruto continua
   com todas as linhas, inclusive as das imagens excluídas aqui.
4. Para cada grupo completo, calcula a **mediana das 3 repetições** de
   `received_size_bytes`, `ssim`, `decode_time_us` e
   `decoded_width × decoded_height` (contagem de pixels) — este é o
   `_ImageMedian`, a observação de uma imagem dentro de uma condição.
5. Agrega os `_ImageMedian` de todas as imagens de uma mesma condição com
   `AggregatedStats.fromValues` (mean/median/standardDeviation/min/max
   sobre as medianas por imagem — ou seja, a **imagem**, não a repetição,
   é a unidade amostral).
6. `meanPixelCount` = média simples da contagem de pixels por imagem
   (usada só para calcular bits-por-pixel no gráfico de dispersão:
   `bitsPerPixel = sizeBytes.mean × 8 / meanPixelCount`).

Cada condição vira uma linha na tabela (`n`, bytes médio, SSIM médio,
tempo médio de decodificação) e um ponto nos dois gráficos: dispersão
bits-por-pixel × SSIM (`SizeVsSsimChart`) e barras de tempo médio de
decodificação por condição (`DecodeTimeBarChart`).

### 3.13 Fronteira de Pareto (`paretoFrontier`, `lib/benchmark/stats/pareto_frontier.dart`)

Aplicada sobre as médias de `sizeBytes`/`ssim` de cada condição (não
sobre resultados individuais). Um ponto (condição) é **dominado** quando
existe outro ponto igual ou melhor nas duas métricas e estritamente
melhor em pelo menos uma:

```text
dominado(candidato) ⟺ ∃ outro:
  outro.bytes ≤ candidato.bytes  ∧  outro.ssim ≥ candidato.ssim
  ∧ (outro.bytes < candidato.bytes  ∨  outro.ssim > candidato.ssim)
```

"Melhor" = menor `received_size_bytes`, maior `ssim`. Não há pesos
combinando as duas métricas numa nota única. Condições não dominadas
recebem uma ⭐ na tabela de resultados.

### 3.14 Metadados de dispositivo (`collectDeviceEnvironment`, `lib/benchmark/data/device_info_provider.dart`)

Via `device_info_plus`: no Android, `manufacturer`/`model` do aparelho e
`"Android <release> (SDK <sdkInt>)"`; no iOS, `"Apple"`/`utsname.machine`
e `"<systemName> <systemVersion>"`. `flutterVersion` vem de uma constante
atualizada manualmente (`flutterVersionForRecordKeeping`, sem API de
runtime para lê-la); `dartVersion` vem de `Platform.version`.

## 4. Constantes centrais do experimento (`lib/benchmark/config/experiment_config.dart`)

| Constante | Valor | Significado |
| --- | --- | --- |
| `qualityLevels` | `[70, 85, 95]` | Níveis de qualidade JPEG/WebP testados |
| `targetLongestSidePx` | `1080` | Lado maior do perfil `target1080`, em pixels |
| `comparisonLongestSidePx` | `1080` | Lado maior da referência de SSIM (igual ao acima) |
| `repetitionsPerVariant` | `3` | Repetições por variante e dispositivo |
| `variantsPerImage` | `12` | 2 formatos × 3 qualidades × 2 resoluções (estrutural, não depende da quantidade de imagens) |
| `intervalBetweenTasks` | `250ms` | Espera fixa entre tarefas consecutivas |
| `maxAttemptsPerTask` | `3` | Tentativas antes de registrar falha definitiva |
| `retryBackoff` | `500ms` | Espera entre tentativas de uma mesma tarefa |
| `httpClientIdleTimeout` (app) | `30s` | Timeout de conexão ociosa no `HttpClient` |
| `keepAliveTimeout`/`headersTimeout` (servidor) | `65s`/`66s` | Timeouts de keep-alive no servidor |
| `seed` (padrão em `BenchmarkScreen`) | `20260724` | Semente do embaralhamento das tarefas |

A quantidade de imagens do dataset, o total de variantes e o total de
tarefas **não são constantes** — não existe `imagesInDataset` nem
`expectedTaskCount` no código. Esses números vêm do `manifest.json` em
tempo de execução (`manifest.variantCount`, contado dinamicamente por
`ManifestLoader`/`BenchmarkProgress`), refletindo o `--count` escolhido em
`dataset/bin/select_images.dart` na geração daquele dataset específico.

## 5. Testes automatizados

- `image_analysis_app/test/` — estatística descritiva, SSIM (imagem
  idêntica ≈ 1, imagens diferentes < 1, validação de faixa), fronteira de
  Pareto com dados sintéticos, serialização/validação do manifesto,
  resolução segura de URLs, serialização CSV, decodificação, download, a
  tela de resultados (agregação por mediana e regra de exclusão).
- `image_analysis_server/test/` — cabeçalhos sem cache, resolução segura
  de caminho (`..`, absolutos, bytes nulos), `/health`.
- `dataset/test/` — geração de ponta a ponta com duas imagens sintéticas,
  conferindo as 12 variantes por imagem e a consistência com o manifesto
  gerado.
