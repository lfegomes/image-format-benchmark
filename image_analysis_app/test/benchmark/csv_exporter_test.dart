import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/data/csv_exporter.dart';
import 'package:image_analysis_app/benchmark/models/benchmark_result.dart';
import 'package:path/path.dart' as p;

BenchmarkResult _sampleResult({
  String? error,
  int? httpStatusCode,
  String deviceLabel = 'Pixel 6 (Android 14)',
}) {
  return BenchmarkResult(
    experimentId: 'exp-1',
    runId: 'run-1',
    sequenceIndex: 0,
    variantId: 'image_001__original__jpeg__q70',
    sourceImageId: 'image_001',
    repetition: 1,
    format: ImageFormat.jpeg,
    quality: 70,
    resolutionProfile: ResolutionProfile.original,
    receivedSizeBytes: 12345,
    downloadTimeUs: 1000,
    decodeTimeUs: 500,
    totalLoadTimeUs: 1500,
    decodedWidth: 2048,
    decodedHeight: 1365,
    decodedMemoryEstimatedBytes: 2048 * 1365 * 4,
    ssim: 0.987654,
    deviceLabel: deviceLabel,
    flutterVersion: '3.44.7',
    operatingSystemVersion: 'Android 14',
    serverBaseUrl: 'http://192.168.1.50:8080/',
    timestamp: DateTime.utc(2026, 7, 24, 12, 0, 0),
    httpStatusCode: httpStatusCode,
    error: error,
  );
}

void main() {
  group('escapeCsvField', () {
    test('não altera valores simples', () {
      expect(escapeCsvField('image_001'), 'image_001');
    });

    test('coloca entre aspas valores com vírgula', () {
      expect(escapeCsvField('a,b'), '"a,b"');
    });

    test('escapa aspas duplas internas', () {
      expect(escapeCsvField('a"b'), '"a""b"');
    });

    test('coloca entre aspas valores com quebra de linha', () {
      expect(escapeCsvField('a\nb'), '"a\nb"');
    });
  });

  group('csvRowFor', () {
    test('produz campos vazios para httpStatusCode e error ausentes', () {
      final row = csvRowFor(_sampleResult());
      final httpStatusIndex = csvColumns.indexOf('http_status_code');
      final errorIndex = csvColumns.indexOf('error');
      expect(row[httpStatusIndex], '');
      expect(row[errorIndex], '');
    });

    test('inclui mensagens de erro com vírgulas corretamente', () {
      final result = _sampleResult(
        error: 'timeout, sem resposta',
        httpStatusCode: 0,
      );
      final row = csvRowFor(result);
      final errorIndex = csvColumns.indexOf('error');
      expect(row[errorIndex], 'timeout, sem resposta');
      expect(encodeCsvRow(row).contains('"timeout, sem resposta"'), isTrue);
    });

    test('deixa campos de medição vazios (não zero) quando ausentes', () {
      final result = BenchmarkResult(
        experimentId: 'exp-1',
        runId: 'run-1',
        sequenceIndex: 0,
        variantId: 'image_001__original__jpeg__q70',
        sourceImageId: 'image_001',
        repetition: 1,
        format: ImageFormat.jpeg,
        quality: 70,
        resolutionProfile: ResolutionProfile.original,
        deviceLabel: 'Pixel 6 (Android 14)',
        flutterVersion: '3.44.7',
        operatingSystemVersion: 'Android 14',
        serverBaseUrl: 'http://192.168.1.50:8080/',
        timestamp: DateTime.utc(2026, 7, 24),
        error: 'falha de download: connection refused',
      );

      final row = csvRowFor(result);

      for (final column in <String>[
        'received_size_bytes',
        'download_time_us',
        'decode_time_us',
        'total_load_time_us',
        'decoded_width',
        'decoded_height',
        'decoded_memory_estimated_bytes',
        'ssim',
      ]) {
        expect(row[csvColumns.indexOf(column)], '',
            reason: '$column deveria ficar vazio, nunca "0"');
      }
      expect(result.isError, isTrue);
    });
  });

  group('CsvExporter', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('csv_exporter_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('escreve o cabeçalho uma única vez e depois as linhas', () async {
      final file = File(p.join(tempDir.path, 'results.csv'));
      final exporter = CsvExporter(file);
      await exporter.open();
      await exporter.appendResult(_sampleResult());
      await exporter.appendResult(_sampleResult());
      await exporter.close();

      final lines = await file.readAsLines();
      expect(lines, hasLength(3));
      expect(lines.first, encodeCsvRow(csvColumns));
    });

    test('reabrir um arquivo existente não duplica o cabeçalho', () async {
      final file = File(p.join(tempDir.path, 'results.csv'));

      final first = CsvExporter(file);
      await first.open();
      await first.appendResult(_sampleResult());
      await first.close();

      final second = CsvExporter(file);
      await second.open();
      await second.appendResult(_sampleResult());
      await second.close();

      final lines = await file.readAsLines();
      expect(lines, hasLength(3));
      expect(lines.where((line) => line == encodeCsvRow(csvColumns)), hasLength(1));
    });

    test('lança ao anexar antes de abrir', () async {
      final file = File(p.join(tempDir.path, 'results.csv'));
      final exporter = CsvExporter(file);
      await expectLater(
        exporter.appendResult(_sampleResult()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
