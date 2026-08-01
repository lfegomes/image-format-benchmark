import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../benchmark/config/experiment_config.dart';
import '../benchmark/models/aggregated_stats.dart';
import '../benchmark/models/benchmark_result.dart';
import '../benchmark/stats/descriptive_stats.dart' as stats;
import '../benchmark/stats/pareto_frontier.dart';
import 'widgets/decode_time_bar_chart.dart';
import 'widgets/size_vs_ssim_chart.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.results, required this.csvFile});

  final List<BenchmarkResult> results;
  final File csvFile;

  /// Agrega por condição tratando a imagem como unidade amostral: as 3
  /// repetições de uma imagem NÃO são amostras independentes, então
  /// primeiro calculamos a mediana das repetições por imagem, e só então
  /// tratamos cada imagem (não cada repetição) como a unidade amostral
  /// agregada por condição.
  ///
  /// **Regra de falhas na agregação (definida a priori, ver README):** o
  /// runner já tenta cada tarefa até `maxAttemptsPerTask` vezes antes de
  /// desistir (`benchmark_runner.dart`). Mesmo assim, uma imagem pode
  /// terminar com menos de [repetitionsPerVariant] repetições bem-sucedidas
  /// numa condição. Never usamos a mediana de um conjunto incompleto (2 de
  /// 3, ou menos) sem dizer isso: essa imagem é **excluída** da condição, e
  /// a contagem de exclusões é exposta na tela, nunca escondida.
  ({List<_ConditionSummary> summaries, int excludedImageConditionCount})
  get _aggregatedResults {
    final successful = results.where((r) => !r.isError).toList();

    final byImageAndCondition = <String, List<BenchmarkResult>>{};
    for (final result in successful) {
      final key = '${result.sourceImageId}#${_ConditionKey.of(result).label}';
      byImageAndCondition.putIfAbsent(key, () => <BenchmarkResult>[]).add(result);
    }

    final perImageMediansByCondition = <_ConditionKey, List<_ImageMedian>>{};
    var excludedCount = 0;
    for (final group in byImageAndCondition.values) {
      if (group.length != repetitionsPerVariant) {
        // Regra documentada: sem as repetitionsPerVariant repetições
        // válidas, a imagem é excluída dessa condição (nunca agregada
        // parcialmente em silêncio).
        excludedCount++;
        continue;
      }

      final conditionKey = _ConditionKey.of(group.first);
      final sizes = group.map((r) => r.receivedSizeBytes!).toList();
      final ssims = group.map((r) => r.ssim!).toList();
      final decodeTimes = group.map((r) => r.decodeTimeUs!).toList();
      final pixelCounts = group.map((r) => r.decodedWidth! * r.decodedHeight!).toList();

      perImageMediansByCondition
          .putIfAbsent(conditionKey, () => <_ImageMedian>[])
          .add(
            _ImageMedian(
              sizeBytes: stats.median(sizes),
              ssim: stats.median(ssims),
              decodeTimeUs: stats.median(decodeTimes),
              pixelCount: stats.median(pixelCounts),
            ),
          );
    }

    final summaries = <_ConditionSummary>[];
    for (final entry in perImageMediansByCondition.entries) {
      final medians = entry.value;
      summaries.add(
        _ConditionSummary(
          key: entry.key,
          sizeBytes: AggregatedStats.fromValues(
            medians.map((m) => m.sizeBytes).toList(),
          ),
          ssim: AggregatedStats.fromValues(medians.map((m) => m.ssim).toList()),
          decodeTimeUs: AggregatedStats.fromValues(
            medians.map((m) => m.decodeTimeUs).toList(),
          ),
          meanPixelCount:
              medians.map((m) => m.pixelCount).reduce((a, b) => a + b) /
              medians.length,
        ),
      );
    }

    summaries.sort((a, b) {
      final byFormat = a.key.format.wireValue.compareTo(b.key.format.wireValue);
      if (byFormat != 0) return byFormat;
      final byProfile = a.key.resolutionProfile.wireValue
          .compareTo(b.key.resolutionProfile.wireValue);
      if (byProfile != 0) return byProfile;
      return a.key.quality.compareTo(b.key.quality);
    });

    return (summaries: summaries, excludedImageConditionCount: excludedCount);
  }

  Future<void> _shareCsv() async {
    if (!await csvFile.exists()) return;
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(csvFile.path)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aggregated = _aggregatedResults;
    final summaries = aggregated.summaries;
    final excludedCount = aggregated.excludedImageConditionCount;
    final paretoPoints = summaries
        .map(
          (s) => ParetoPoint<_ConditionKey>(
            item: s.key,
            sizeBytes: s.sizeBytes.mean,
            ssim: s.ssim.mean,
          ),
        )
        .toList();
    final frontierKeys = paretoFrontier(paretoPoints).map((p) => p.item).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados'),
        actions: [
          IconButton(
            onPressed: _shareCsv,
            icon: const Icon(Icons.share),
            tooltip: 'Exportar/compartilhar CSV',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (excludedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$excludedCount imagem(ens) excluída(s) da '
                'agregação por não ter $repetitionsPerVariant repetições '
                'válidas na condição (regra de falha — ver README). '
                'O CSV bruto continua contendo todas as '
                'repetições, inclusive as das imagens excluídas aqui.',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            _buildTable(summaries, frontierKeys),
            const SizedBox(height: 24),
            const Text(
              'Bytes por pixel × SSIM',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(
              height: 240,
              child: SizeVsSsimChart(
                points: <SizeVsSsimPoint>[
                  for (final s in summaries)
                    SizeVsSsimPoint(
                      bitsPerPixel: (s.sizeBytes.mean * 8) / s.meanPixelCount,
                      ssim: s.ssim.mean,
                      isWebp: s.key.format == ImageFormat.webp,
                      label: s.key.label,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tempo de decodificação por condição',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(
              height: 260,
              child: DecodeTimeBarChart(
                bars: <DecodeTimeBar>[
                  for (final s in summaries)
                    DecodeTimeBar(
                      label: s.key.shortLabel,
                      meanDecodeTimeUs: s.decodeTimeUs.mean,
                      isWebp: s.key.format == ImageFormat.webp,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<_ConditionSummary> summaries, Set<_ConditionKey> frontierKeys) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const <DataColumn>[
          DataColumn(label: Text('Formato')),
          DataColumn(label: Text('Qualidade')),
          DataColumn(label: Text('Resolução')),
          DataColumn(label: Text('n')),
          DataColumn(label: Text('Bytes (média)')),
          DataColumn(label: Text('SSIM (média)')),
          DataColumn(label: Text('Decode (média, µs)')),
          DataColumn(label: Text('Pareto')),
        ],
        rows: <DataRow>[
          for (final s in summaries)
            DataRow(
              cells: <DataCell>[
                DataCell(Text(s.key.format.wireValue)),
                DataCell(Text('${s.key.quality}')),
                DataCell(Text(s.key.resolutionProfile.wireValue)),
                DataCell(Text('${s.sizeBytes.sampleCount}')),
                DataCell(Text(s.sizeBytes.mean.toStringAsFixed(0))),
                DataCell(Text(s.ssim.mean.toStringAsFixed(4))),
                DataCell(Text(s.decodeTimeUs.mean.toStringAsFixed(0))),
                DataCell(
                  frontierKeys.contains(s.key)
                      ? const Icon(Icons.star, color: Colors.amber, size: 18)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ConditionKey {
  const _ConditionKey({
    required this.format,
    required this.quality,
    required this.resolutionProfile,
  });

  factory _ConditionKey.of(BenchmarkResult result) => _ConditionKey(
    format: result.format,
    quality: result.quality,
    resolutionProfile: result.resolutionProfile,
  );

  final ImageFormat format;
  final int quality;
  final ResolutionProfile resolutionProfile;

  String get label => '${format.wireValue} q$quality ${resolutionProfile.wireValue}';
  String get shortLabel => '${format.wireValue[0]}$quality\n${resolutionProfile == ResolutionProfile.original ? 'orig' : '1080'}';

  @override
  bool operator ==(Object other) =>
      other is _ConditionKey &&
      other.format == format &&
      other.quality == quality &&
      other.resolutionProfile == resolutionProfile;

  @override
  int get hashCode => Object.hash(format, quality, resolutionProfile);
}

class _ConditionSummary {
  const _ConditionSummary({
    required this.key,
    required this.sizeBytes,
    required this.ssim,
    required this.decodeTimeUs,
    required this.meanPixelCount,
  });

  final _ConditionKey key;
  final AggregatedStats sizeBytes;
  final AggregatedStats ssim;
  final AggregatedStats decodeTimeUs;
  final double meanPixelCount;
}

/// Mediana das repetições de uma imagem dentro de uma condição — a unidade
/// amostral usada para agregar por condição.
class _ImageMedian {
  const _ImageMedian({
    required this.sizeBytes,
    required this.ssim,
    required this.decodeTimeUs,
    required this.pixelCount,
  });

  final num sizeBytes;
  final num ssim;
  final num decodeTimeUs;
  final num pixelCount;
}
