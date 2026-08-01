import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/data/csv_exporter.dart';
import 'package:image_analysis_app/benchmark/data/reference_store.dart';
import 'package:image_analysis_app/benchmark/data/result_store.dart';
import 'package:image_analysis_app/benchmark/models/device_environment.dart';
import 'package:image_analysis_app/benchmark/models/experiment_manifest.dart';
import 'package:image_analysis_app/benchmark/models/image_variant.dart';
import 'package:image_analysis_app/benchmark/runner/benchmark_progress.dart';
import 'package:image_analysis_app/benchmark/runner/benchmark_runner.dart';
import 'package:path/path.dart' as p;

Uint8List _encodePng(int width, int height, int seed) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = ((x + y + seed) * 17) % 256;
      image.setPixelRgb(x, y, v, (v + 40) % 256, (v + 90) % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

const _deviceEnvironment = DeviceEnvironment(
  deviceLabel: 'Test Device (Test OS)',
  manufacturer: 'Test',
  model: 'Test Device',
  operatingSystemVersion: 'Test OS',
  flutterVersion: '3.44.7',
  dartVersion: '3.12.2',
);

void main() {
  group('buildShuffledTasks', () {
    test('gera variants.length * repetitionsPerVariant tarefas com '
        'sequenceIndex único e determinístico para uma mesma semente', () {
      final variantBytes = _encodePng(8, 8, 0);
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'test',
        generatedAt: DateTime.utc(2026, 7, 24),
        sourceImageCount: 2,
        variantCount: 2,
        repetitionsPerVariant: repetitionsPerVariant,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{},
        variants: <ImageVariant>[
          ImageVariant(
            variantId: 'a',
            sourceImageId: 'image_001',
            relativeUrl: 'variants/a.jpg',
            referenceUrl: 'references/image_001.png',
            format: ImageFormat.jpeg,
            quality: 70,
            resolutionProfile: ResolutionProfile.original,
            manifestSizeBytes: variantBytes.length,
            expectedWidth: 8,
            expectedHeight: 8,
          ),
          ImageVariant(
            variantId: 'b',
            sourceImageId: 'image_002',
            relativeUrl: 'variants/b.jpg',
            referenceUrl: 'references/image_002.png',
            format: ImageFormat.webp,
            quality: 85,
            resolutionProfile: ResolutionProfile.target1080,
            manifestSizeBytes: variantBytes.length,
            expectedWidth: 8,
            expectedHeight: 8,
          ),
        ],
      );

      final first = buildShuffledTasks(manifest: manifest, seed: 42);
      final second = buildShuffledTasks(manifest: manifest, seed: 42);

      expect(first, hasLength(2 * repetitionsPerVariant));
      expect(
        first.map((t) => t.sequenceIndex).toSet(),
        Set<int>.from(List.generate(2 * repetitionsPerVariant, (i) => i)),
      );
      // Mesma semente produz a mesma ordem.
      expect(
        first.map((t) => '${t.variant.variantId}#${t.repetition}').toList(),
        second.map((t) => '${t.variant.variantId}#${t.repetition}').toList(),
      );
    });
  });

  group('BenchmarkRunner', () {
    late HttpServer server;
    late Uri baseUri;
    late Directory tempDir;
    late Uint8List variantBytes;
    late Uint8List referenceBytes;
    late Map<String, int> requestCounts;
    late int flakyFailuresRemaining;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('benchmark_runner_test_');
      variantBytes = _encodePng(16, 16, 1);
      referenceBytes = variantBytes; // SSIM ~1 quando idênticas.
      requestCounts = <String, int>{};
      flakyFailuresRemaining = 2;

      server = await HttpServer.bind('127.0.0.1', 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
      server.listen((request) async {
        final path = request.uri.path;
        requestCounts[path] = (requestCounts[path] ?? 0) + 1;
        if (path == '/variants/ok.jpg') {
          request.response.statusCode = 200;
          request.response.add(variantBytes);
        } else if (path == '/references/image_001.png') {
          request.response.statusCode = 200;
          request.response.add(referenceBytes);
        } else if (path == '/variants/broken.jpg') {
          request.response.statusCode = 404;
        } else if (path == '/variants/flaky.jpg') {
          if (flakyFailuresRemaining > 0) {
            flakyFailuresRemaining--;
            request.response.statusCode = 503;
          } else {
            request.response.statusCode = 200;
            request.response.add(variantBytes);
          }
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tempDir.deleteSync(recursive: true);
    });

    ImageVariant okVariant() => ImageVariant(
      variantId: 'image_001__original__jpeg__q70',
      sourceImageId: 'image_001',
      relativeUrl: 'variants/ok.jpg',
      referenceUrl: 'references/image_001.png',
      format: ImageFormat.jpeg,
      quality: 70,
      resolutionProfile: ResolutionProfile.original,
      manifestSizeBytes: variantBytes.length,
      expectedWidth: 16,
      expectedHeight: 16,
    );

    ImageVariant brokenVariant() => ImageVariant(
      variantId: 'image_001__original__jpeg__q999',
      sourceImageId: 'image_001',
      relativeUrl: 'variants/broken.jpg',
      referenceUrl: 'references/image_001.png',
      format: ImageFormat.jpeg,
      quality: 95,
      resolutionProfile: ResolutionProfile.original,
      manifestSizeBytes: 1,
      expectedWidth: 16,
      expectedHeight: 16,
    );

    ImageVariant flakyVariant() => ImageVariant(
      variantId: 'image_001__original__jpeg__q80',
      sourceImageId: 'image_001',
      relativeUrl: 'variants/flaky.jpg',
      referenceUrl: 'references/image_001.png',
      format: ImageFormat.jpeg,
      quality: 85,
      resolutionProfile: ResolutionProfile.original,
      manifestSizeBytes: variantBytes.length,
      expectedWidth: 16,
      expectedHeight: 16,
    );

    Future<ResultStore> buildResultStore() async {
      final store = ResultStore(CsvExporter(File(p.join(tempDir.path, 'r.csv'))));
      await store.open();
      return store;
    }

    test('executa todas as tarefas com sucesso, calcula SSIM uma vez por '
        'variante e persiste cada resultado', () async {
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'test',
        generatedAt: DateTime.utc(2026, 7, 24),
        sourceImageCount: 1,
        variantCount: 1,
        repetitionsPerVariant: repetitionsPerVariant,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{},
        variants: <ImageVariant>[okVariant()],
      );

      final referenceStore = ReferenceStore();
      await referenceStore.loadAll(baseUri, manifest);

      final resultStore = await buildResultStore();
      final progress = BenchmarkProgress(totalTasks: repetitionsPerVariant);

      final runner = BenchmarkRunner(
        baseUri: baseUri,
        manifest: manifest,
        experimentId: 'exp-test',
        seed: 7,
        deviceEnvironment: _deviceEnvironment,
        resultStore: resultStore,
        referenceStore: referenceStore,
        taskInterval: Duration.zero,
      );

      await runner.run(progress);
      runner.dispose();
      await resultStore.close();

      expect(progress.phase, BenchmarkPhase.completed);
      expect(progress.completedTasks, repetitionsPerVariant);
      expect(progress.successCount, repetitionsPerVariant);
      expect(progress.failureCount, 0);
      expect(resultStore.results, hasLength(repetitionsPerVariant));

      for (final result in resultStore.results) {
        expect(result.isError, isFalse);
        expect(result.receivedSizeBytes, variantBytes.length);
        expect(result.ssim, closeTo(1.0, 1e-6));
        expect(result.decodedWidth, 16);
        expect(result.decodedHeight, 16);
        expect(result.totalLoadTimeUs, result.downloadTimeUs! + result.decodeTimeUs!);
      }

      final sequenceIndices = resultStore.results.map((r) => r.sequenceIndex).toSet();
      expect(sequenceIndices, <int>{0, 1, 2});

      final csvLines = File(p.join(tempDir.path, 'r.csv')).readAsLinesSync();
      expect(csvLines, hasLength(repetitionsPerVariant + 1));
    });

    test('tarefa com status HTTP de erro gera BenchmarkResult com error '
        'preenchido e campos de medição vazios, sem interromper a rodada', () async {
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'test',
        generatedAt: DateTime.utc(2026, 7, 24),
        sourceImageCount: 1,
        variantCount: 1,
        repetitionsPerVariant: repetitionsPerVariant,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{},
        variants: <ImageVariant>[brokenVariant()],
      );

      final resultStore = await buildResultStore();
      final progress = BenchmarkProgress(totalTasks: repetitionsPerVariant);

      final runner = BenchmarkRunner(
        baseUri: baseUri,
        manifest: manifest,
        experimentId: 'exp-test',
        seed: 7,
        deviceEnvironment: _deviceEnvironment,
        resultStore: resultStore,
        referenceStore: ReferenceStore(),
        taskInterval: Duration.zero,
      );

      await runner.run(progress);
      runner.dispose();
      await resultStore.close();

      expect(progress.failureCount, repetitionsPerVariant);
      expect(progress.successCount, 0);
      for (final result in resultStore.results) {
        expect(result.isError, isTrue);
        expect(result.error, isNotNull);
        expect(result.receivedSizeBytes, isNull);
        expect(result.downloadTimeUs, isNull);
        expect(result.ssim, isNull);
      }
    });

    test('regra de retry: uma falha transitória (503) se recupera dentro '
        'de maxAttemptsPerTask tentativas e o resultado final é sucesso', () async {
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'test',
        generatedAt: DateTime.utc(2026, 7, 24),
        sourceImageCount: 1,
        variantCount: 1,
        repetitionsPerVariant: repetitionsPerVariant,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{},
        variants: <ImageVariant>[flakyVariant()],
      );

      final referenceStore = ReferenceStore();
      await referenceStore.loadAll(baseUri, manifest);

      final resultStore = await buildResultStore();
      final progress = BenchmarkProgress(totalTasks: repetitionsPerVariant);

      final runner = BenchmarkRunner(
        baseUri: baseUri,
        manifest: manifest,
        experimentId: 'exp-test',
        seed: 7,
        deviceEnvironment: _deviceEnvironment,
        resultStore: resultStore,
        referenceStore: referenceStore,
        taskInterval: Duration.zero,
      );

      await runner.run(progress);
      runner.dispose();
      await resultStore.close();

      // As 2 primeiras requisições ao servidor falham (503): uma é o
      // aquecimento (descartado) e a outra é a 1ª tentativa da 1ª tarefa
      // processada. A partir da 3ª requisição, o servidor sempre responde
      // 200 — então, com maxAttemptsPerTask = 3, a tarefa se recupera e
      // todas as 3 repetições terminam com sucesso.
      expect(progress.successCount, repetitionsPerVariant);
      expect(progress.failureCount, 0);
      expect(requestCounts['/variants/flaky.jpg'], greaterThan(repetitionsPerVariant));
      for (final result in resultStore.results) {
        expect(result.isError, isFalse);
      }
    });

    test('cancelamento interrompe antes da próxima tarefa sem perder '
        'resultados já persistidos', () async {
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'test',
        generatedAt: DateTime.utc(2026, 7, 24),
        sourceImageCount: 2,
        variantCount: 2,
        repetitionsPerVariant: repetitionsPerVariant,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{},
        variants: <ImageVariant>[
          okVariant(),
          ImageVariant(
            variantId: 'image_001__target1080__jpeg__q70',
            sourceImageId: 'image_001',
            relativeUrl: 'variants/ok.jpg',
            referenceUrl: 'references/image_001.png',
            format: ImageFormat.jpeg,
            quality: 70,
            resolutionProfile: ResolutionProfile.target1080,
            manifestSizeBytes: variantBytes.length,
            expectedWidth: 16,
            expectedHeight: 16,
          ),
        ],
      );

      final referenceStore = ReferenceStore();
      await referenceStore.loadAll(baseUri, manifest);

      final resultStore = await buildResultStore();
      final progress = BenchmarkProgress(totalTasks: 2 * repetitionsPerVariant);

      final runner = BenchmarkRunner(
        baseUri: baseUri,
        manifest: manifest,
        experimentId: 'exp-test',
        seed: 7,
        deviceEnvironment: _deviceEnvironment,
        resultStore: resultStore,
        referenceStore: referenceStore,
        taskInterval: const Duration(milliseconds: 50),
      );

      progress.addListener(() {
        if (progress.completedTasks == 1) {
          runner.cancel();
        }
      });

      await runner.run(progress);
      runner.dispose();
      await resultStore.close();

      expect(progress.completedTasks, 1);
      expect(resultStore.results, hasLength(1));
      expect(progress.phase, BenchmarkPhase.completed);
    });
  });
}
