import 'dart:math';
import 'dart:typed_data';

import '../config/experiment_config.dart';
import '../data/reference_store.dart';
import '../data/result_store.dart';
import '../decoding/image_decoder.dart';
import '../models/benchmark_result.dart';
import '../models/benchmark_task.dart';
import '../models/device_environment.dart';
import '../models/experiment_manifest.dart';
import '../models/image_variant.dart';
import '../network/image_downloader.dart';
import '../quality/ssim.dart';
import 'benchmark_progress.dart';

/// Monta as `variants.length × repetitionsPerVariant` tarefas, embaralha
/// com uma semente fixa e atribui `sequenceIndex` de forma determinística
/// após o embaralhamento.
List<BenchmarkTask> buildShuffledTasks({
  required ExperimentManifest manifest,
  required int seed,
}) {
  final tasks = <BenchmarkTask>[];
  for (final variant in manifest.variants) {
    for (
      var repetition = 1;
      repetition <= repetitionsPerVariant;
      repetition++
    ) {
      tasks.add(
        BenchmarkTask(variant: variant, repetition: repetition, sequenceIndex: -1),
      );
    }
  }

  tasks.shuffle(Random(seed));

  return <BenchmarkTask>[
    for (var i = 0; i < tasks.length; i++) tasks[i].copyWithSequenceIndex(i),
  ];
}

/// Executa as tarefas sequencialmente (nunca em paralelo, para não
/// tornar os tempos de download menos comparáveis entre tarefas),
/// seguindo sempre o mesmo pipeline por tarefa: download cronometrado,
/// decodificação cronometrada, SSIM fora dos cronômetros, persistência
/// imediata e intervalo fixo entre tarefas (ver
/// docs/architecture-notes.md, "Pipeline de uma tarefa").
class BenchmarkRunner {
  BenchmarkRunner({
    required this.baseUri,
    required this.manifest,
    required this.experimentId,
    required this.seed,
    required this.deviceEnvironment,
    required this.resultStore,
    required this.referenceStore,
    ImageDownloader? downloader,
    Duration? taskInterval,
  }) : _downloader = downloader ?? ImageDownloader(),
       taskInterval = taskInterval ?? intervalBetweenTasks;

  final Uri baseUri;
  final ExperimentManifest manifest;
  final String experimentId;
  final int seed;
  final DeviceEnvironment deviceEnvironment;
  final ResultStore resultStore;
  final ReferenceStore referenceStore;
  final Duration taskInterval;

  final ImageDownloader _downloader;
  final Map<String, double> _ssimCache = <String, double>{};
  bool _cancelRequested = false;

  bool get cancelRequested => _cancelRequested;

  /// Executa todas as tarefas, atualizando [progress] a cada passo.
  /// [progress] deve ter sido criado com `totalTasks` igual a
  /// `manifest.variants.length * repetitionsPerVariant`.
  ///
  /// Antes da primeira tarefa, faz um aquecimento (download + decodificação
  /// de uma variante, descartado) para abrir a conexão TCP/HTTP e aquecer
  /// o JIT antes de cronometrar qualquer medição real. Falhas no
  /// aquecimento são ignoradas — não fazem parte dos resultados.
  Future<void> run(BenchmarkProgress progress) async {
    final tasks = buildShuffledTasks(manifest: manifest, seed: seed);

    if (tasks.isNotEmpty) {
      await _warmUp(tasks.first.variant);
    }

    progress.start();

    for (final task in tasks) {
      if (_cancelRequested) break;

      progress.updateCurrentTask(
        variantId: task.variant.variantId,
        repetition: task.repetition,
        sequenceIndex: task.sequenceIndex,
      );

      final result = await _runTaskWithRetries(task);
      await resultStore.record(result);

      if (result.isError) {
        progress.recordFailure();
      } else {
        progress.recordSuccess();
      }

      if (_cancelRequested) break;
      await Future<void>.delayed(taskInterval);
    }

    progress.complete();
  }

  Future<void> _warmUp(ImageVariant variant) async {
    try {
      final downloadResult = await _downloader.download(
        baseUri: baseUri,
        variant: variant,
        runId: '$experimentId-warmup',
      );
      final decodeResult = await decodeImage(downloadResult.bytes);
      decodeResult.image.dispose();
    } on Exception catch (e) {
      // Aquecimento é descartável: uma falha aqui não impede a rodada real
      // (a conectividade já foi validada por /health e pelo manifesto na
      // tela de configuração), só fica registrada no log para diagnóstico.
      // ignore: avoid_print
      print('Aquecimento falhou (ignorado, fora dos resultados): $e');
    }
  }

  /// Regra de falhas definida a priori (ver [maxAttemptsPerTask] em
  /// `experiment_config.dart` e a seção "Regra de falhas" do README):
  /// tenta a tarefa até `maxAttemptsPerTask` vezes, cada uma com um
  /// `runId` novo (nova requisição HTTP de verdade, não reaproveitamento).
  /// Só o resultado da última tentativa é persistido; tentativas
  /// anteriores que falharam ficam apenas no log do console.
  Future<BenchmarkResult> _runTaskWithRetries(BenchmarkTask task) async {
    for (var attempt = 1; attempt <= maxAttemptsPerTask; attempt++) {
      final result = await _runSingleTask(task, attempt);
      if (!result.isError) {
        return result;
      }
      if (attempt < maxAttemptsPerTask) {
        // ignore: avoid_print
        print(
          'Tarefa ${task.variant.variantId} rep.${task.repetition} '
          'falhou na tentativa $attempt/$maxAttemptsPerTask '
          '(${result.error}); tentando novamente.',
        );
        await Future<void>.delayed(retryBackoff);
      } else {
        return result;
      }
    }
    // Inatingível: o loop sempre retorna dentro do for.
    throw StateError('_runTaskWithRetries não retornou um resultado');
  }

  /// Solicita o cancelamento: a tarefa em andamento é concluída e seu
  /// resultado persistido, mas nenhuma tarefa nova é iniciada.
  void cancel() {
    _cancelRequested = true;
  }

  void dispose() {
    _downloader.close();
    referenceStore.close();
  }

  Future<BenchmarkResult> _runSingleTask(BenchmarkTask task, int attempt) async {
    final variant = task.variant;
    final runId = '$experimentId-${task.sequenceIndex}-a$attempt';
    final timestamp = DateTime.now().toUtc();

    final DownloadResult downloadResult;
    try {
      downloadResult = await _downloader.download(
        baseUri: baseUri,
        variant: variant,
        runId: runId,
      );
    } on DownloadException catch (e) {
      return _errorResult(task, runId, timestamp, e.toString(), e.httpStatusCode);
    }

    final DecodeResult decodeResult;
    try {
      decodeResult = await decodeImage(downloadResult.bytes);
    } on DecodeException catch (e) {
      return _errorResult(
        task,
        runId,
        timestamp,
        e.toString(),
        downloadResult.httpStatusCode,
      );
    }

    if (decodeResult.width != variant.expectedWidth ||
        decodeResult.height != variant.expectedHeight) {
      final actualWidth = decodeResult.width;
      final actualHeight = decodeResult.height;
      decodeResult.image.dispose();
      return _errorResult(
        task,
        runId,
        timestamp,
        'Dimensão decodificada (${actualWidth}x$actualHeight) diverge do '
        'manifesto (${variant.expectedWidth}x${variant.expectedHeight})',
        downloadResult.httpStatusCode,
      );
    }

    final memoryBytes = estimatedMemoryBytes(
      decodeResult.width,
      decodeResult.height,
    );
    decodeResult.image.dispose();

    final double ssimValue;
    try {
      ssimValue = await _ssimFor(variant, downloadResult.bytes);
    } on Exception catch (e) {
      return _errorResult(
        task,
        runId,
        timestamp,
        e.toString(),
        downloadResult.httpStatusCode,
      );
    }

    return BenchmarkResult(
      experimentId: experimentId,
      runId: runId,
      sequenceIndex: task.sequenceIndex,
      variantId: variant.variantId,
      sourceImageId: variant.sourceImageId,
      repetition: task.repetition,
      format: variant.format,
      quality: variant.quality,
      resolutionProfile: variant.resolutionProfile,
      deviceLabel: deviceEnvironment.deviceLabel,
      flutterVersion: deviceEnvironment.flutterVersion,
      operatingSystemVersion: deviceEnvironment.operatingSystemVersion,
      serverBaseUrl: baseUri.toString(),
      timestamp: timestamp,
      receivedSizeBytes: downloadResult.bytes.length,
      downloadTimeUs: downloadResult.downloadTimeUs,
      decodeTimeUs: decodeResult.decodeTimeUs,
      totalLoadTimeUs: downloadResult.downloadTimeUs + decodeResult.decodeTimeUs,
      decodedWidth: decodeResult.width,
      decodedHeight: decodeResult.height,
      decodedMemoryEstimatedBytes: memoryBytes,
      ssim: ssimValue,
      httpStatusCode: downloadResult.httpStatusCode,
    );
  }

  /// Calcula o SSIM uma única vez por `variantId` e reutiliza o valor em
  /// memória nas repetições seguintes.
  Future<double> _ssimFor(ImageVariant variant, Uint8List variantBytes) async {
    final cached = _ssimCache[variant.variantId];
    if (cached != null) {
      return cached;
    }
    final referenceBytes = referenceStore.referenceFor(variant.sourceImageId);
    final value = computeSsimFromBytes(
      imageBytes: variantBytes,
      referenceBytes: referenceBytes,
    );
    _ssimCache[variant.variantId] = value;
    return value;
  }

  BenchmarkResult _errorResult(
    BenchmarkTask task,
    String runId,
    DateTime timestamp,
    String error,
    int? httpStatusCode,
  ) {
    final variant = task.variant;
    return BenchmarkResult(
      experimentId: experimentId,
      runId: runId,
      sequenceIndex: task.sequenceIndex,
      variantId: variant.variantId,
      sourceImageId: variant.sourceImageId,
      repetition: task.repetition,
      format: variant.format,
      quality: variant.quality,
      resolutionProfile: variant.resolutionProfile,
      deviceLabel: deviceEnvironment.deviceLabel,
      flutterVersion: deviceEnvironment.flutterVersion,
      operatingSystemVersion: deviceEnvironment.operatingSystemVersion,
      serverBaseUrl: baseUri.toString(),
      timestamp: timestamp,
      httpStatusCode: httpStatusCode,
      error: error,
    );
  }
}
