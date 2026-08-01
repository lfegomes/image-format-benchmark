import '../stats/descriptive_stats.dart' as stats;

/// Resumo estatístico de uma amostra de valores (ex.: tamanho em bytes,
/// tempo de decodificação) para uma condição (formato × qualidade ×
/// resolução).
class AggregatedStats {
  const AggregatedStats({
    required this.mean,
    required this.median,
    required this.standardDeviation,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  factory AggregatedStats.fromValues(List<num> values) {
    return AggregatedStats(
      mean: stats.mean(values),
      median: stats.median(values),
      standardDeviation: stats.standardDeviation(values),
      min: stats.minOf(values),
      max: stats.maxOf(values),
      sampleCount: values.length,
    );
  }

  final double mean;
  final double median;
  final double standardDeviation;
  final num min;
  final num max;
  final int sampleCount;
}
