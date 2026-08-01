/// Estatística descritiva pura, sem dependência de I/O.
library;

import 'dart:math' as math;

class EmptySampleError extends ArgumentError {
  EmptySampleError() : super('Amostra vazia');
}

double mean(List<num> values) {
  if (values.isEmpty) throw EmptySampleError();
  return values.reduce((a, b) => a + b) / values.length;
}

double median(List<num> values) {
  if (values.isEmpty) throw EmptySampleError();
  final sorted = List<num>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle].toDouble();
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Desvio-padrão amostral (divisor n-1). Retorna 0 para amostras com menos
/// de 2 valores, já que a variância amostral não é definida nesse caso.
double standardDeviation(List<num> values) {
  if (values.isEmpty) throw EmptySampleError();
  if (values.length < 2) return 0;
  final avg = mean(values);
  final sumOfSquares = values
      .map((value) => (value - avg) * (value - avg))
      .reduce((a, b) => a + b);
  return math.sqrt(sumOfSquares / (values.length - 1));
}

num minOf(List<num> values) {
  if (values.isEmpty) throw EmptySampleError();
  return values.reduce((a, b) => a < b ? a : b);
}

num maxOf(List<num> values) {
  if (values.isEmpty) throw EmptySampleError();
  return values.reduce((a, b) => a > b ? a : b);
}

/// Redução percentual de [comparison] em relação a [baseline]. Positivo
/// significa que [comparison] é menor que [baseline].
double percentageReduction({required num baseline, required num comparison}) {
  if (baseline == 0) {
    throw ArgumentError('baseline não pode ser zero');
  }
  return (baseline - comparison) / baseline * 100;
}
