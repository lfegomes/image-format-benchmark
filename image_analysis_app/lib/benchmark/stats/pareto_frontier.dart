/// Fronteira de Pareto simples entre bytes (menor é melhor) e SSIM (maior é
/// melhor).
library;

class ParetoPoint<T> {
  const ParetoPoint({
    required this.item,
    required this.sizeBytes,
    required this.ssim,
  });

  final T item;
  final num sizeBytes;
  final double ssim;
}

/// Retorna os pontos não dominados: um ponto é dominado quando existe outro
/// igual ou melhor em ambas as métricas e estritamente melhor em pelo menos
/// uma delas.
List<ParetoPoint<T>> paretoFrontier<T>(List<ParetoPoint<T>> points) {
  final frontier = <ParetoPoint<T>>[];

  for (final candidate in points) {
    final isDominated = points.any((other) {
      if (identical(other, candidate)) return false;
      final atLeastAsGood =
          other.sizeBytes <= candidate.sizeBytes && other.ssim >= candidate.ssim;
      final strictlyBetter =
          other.sizeBytes < candidate.sizeBytes || other.ssim > candidate.ssim;
      return atLeastAsGood && strictlyBetter;
    });

    if (!isDominated) {
      frontier.add(candidate);
    }
  }

  return frontier;
}
