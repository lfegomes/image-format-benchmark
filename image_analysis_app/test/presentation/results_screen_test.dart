import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/models/benchmark_result.dart';
import 'package:image_analysis_app/presentation/results_screen.dart';

BenchmarkResult _result({
  required String sourceImageId,
  required int repetition,
  required int decodeTimeUs,
}) {
  return BenchmarkResult(
    experimentId: 'exp-1',
    runId: 'run-$sourceImageId-$repetition',
    sequenceIndex: repetition,
    variantId: '${sourceImageId}__original__jpeg__q70',
    sourceImageId: sourceImageId,
    repetition: repetition,
    format: ImageFormat.jpeg,
    quality: 70,
    resolutionProfile: ResolutionProfile.original,
    deviceLabel: 'Pixel 6 (Android 14)',
    flutterVersion: '3.44.7',
    operatingSystemVersion: 'Android 14',
    serverBaseUrl: 'http://192.168.1.50:8080/',
    timestamp: DateTime.utc(2026, 7, 24),
    receivedSizeBytes: 10000,
    downloadTimeUs: 5000,
    decodeTimeUs: decodeTimeUs,
    totalLoadTimeUs: 5000 + decodeTimeUs,
    decodedWidth: 100,
    decodedHeight: 100,
    decodedMemoryEstimatedBytes: 100 * 100 * 4,
    ssim: 0.95,
  );
}

BenchmarkResult _errorResult({
  required String sourceImageId,
  required int repetition,
}) {
  return BenchmarkResult(
    experimentId: 'exp-1',
    runId: 'run-$sourceImageId-$repetition',
    sequenceIndex: repetition,
    variantId: '${sourceImageId}__original__jpeg__q70',
    sourceImageId: sourceImageId,
    repetition: repetition,
    format: ImageFormat.jpeg,
    quality: 70,
    resolutionProfile: ResolutionProfile.original,
    deviceLabel: 'Pixel 6 (Android 14)',
    flutterVersion: '3.44.7',
    operatingSystemVersion: 'Android 14',
    serverBaseUrl: 'http://192.168.1.50:8080/',
    timestamp: DateTime.utc(2026, 7, 24),
    error: 'falha simulada',
  );
}

void main() {
  testWidgets(
    'exclui da agregação uma imagem que não completou as 3 repetições '
    'válidas, e mostra a contagem de exclusão — nunca agrega em silêncio',
    (WidgetTester tester) async {
      final results = <BenchmarkResult>[
        // image_001: 3 repetições válidas -> entra na agregação.
        _result(sourceImageId: 'image_001', repetition: 1, decodeTimeUs: 100),
        _result(sourceImageId: 'image_001', repetition: 2, decodeTimeUs: 100),
        _result(sourceImageId: 'image_001', repetition: 3, decodeTimeUs: 100),
        // image_002: só 2 repetições válidas (1 falhou mesmo após retry no
        // runner) -> deve ser EXCLUÍDA, nunca agregada com mediana de 2.
        _result(sourceImageId: 'image_002', repetition: 1, decodeTimeUs: 999),
        _result(sourceImageId: 'image_002', repetition: 2, decodeTimeUs: 999),
        _errorResult(sourceImageId: 'image_002', repetition: 3),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen(
            results: results,
            csvFile: File('/tmp/does-not-need-to-exist.csv'),
          ),
        ),
      );
      await tester.pump();

      // "n" na tabela deve ser 1 (só image_001), nunca 2.
      expect(
        find.descendant(of: find.byType(DataTable), matching: find.text('1')),
        findsOneWidget,
      );
      // O tempo "999" de image_002 nunca deveria aparecer agregado —
      // confirma que ela não entrou silenciosamente com mediana de 2 reps.
      expect(find.text('999'), findsNothing);
      // A exclusão precisa ficar visível na tela, não silenciosa.
      expect(find.textContaining('excluída'), findsOneWidget);
    },
  );

  testWidgets(
    'agrega por mediana das repetições por imagem, não pela média bruta '
    'das repetições',
    (WidgetTester tester) async {
      // Uma única imagem, 3 repetições com tempos de decodificação
      // assimétricos: mediana = 100, média = 200. Se a tela agregasse as
      // repetições brutas como se fossem amostras independentes, a coluna
      // mostraria "200"; o comportamento correto mostra "100".
      final results = <BenchmarkResult>[
        _result(sourceImageId: 'image_001', repetition: 1, decodeTimeUs: 100),
        _result(sourceImageId: 'image_001', repetition: 2, decodeTimeUs: 100),
        _result(sourceImageId: 'image_001', repetition: 3, decodeTimeUs: 400),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen(
            results: results,
            csvFile: File('/tmp/does-not-need-to-exist.csv'),
          ),
        ),
      );
      await tester.pump();

      // "100" aparece na tabela e no gráfico de barras (mesmo valor,
      // consistente); em nenhum lugar deve aparecer a média bruta "200".
      expect(
        find.descendant(of: find.byType(DataTable), matching: find.text('100')),
        findsOneWidget,
      );
      expect(find.text('200'), findsNothing);

      // "n" (coluna de contagem) deve ser 1 imagem, não 3 repetições.
      expect(
        find.descendant(of: find.byType(DataTable), matching: find.text('1')),
        findsOneWidget,
      );
    },
  );
}
