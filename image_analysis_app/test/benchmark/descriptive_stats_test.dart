import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/stats/descriptive_stats.dart';

void main() {
  group('mean', () {
    test('calcula a média aritmética', () {
      expect(mean([1, 2, 3, 4]), 2.5);
    });

    test('lança em amostra vazia', () {
      expect(() => mean(<num>[]), throwsA(isA<EmptySampleError>()));
    });
  });

  group('median', () {
    test('calcula a mediana com número ímpar de valores', () {
      expect(median([5, 1, 3]), 3);
    });

    test('calcula a mediana com número par de valores', () {
      expect(median([1, 2, 3, 4]), 2.5);
    });
  });

  group('standardDeviation', () {
    test('calcula o desvio-padrão amostral', () {
      // Valores 2,4,4,4,5,5,7,9 -> desvio-padrão amostral conhecido = 2.13809...
      final result = standardDeviation([2, 4, 4, 4, 5, 5, 7, 9]);
      expect(result, closeTo(2.13809, 0.0001));
    });

    test('retorna 0 para amostra de um único valor', () {
      expect(standardDeviation([42]), 0);
    });
  });

  group('minOf / maxOf', () {
    test('encontram o mínimo e o máximo', () {
      expect(minOf([5, 1, 9, 3]), 1);
      expect(maxOf([5, 1, 9, 3]), 9);
    });
  });

  group('percentageReduction', () {
    test('calcula redução percentual positiva quando comparison é menor', () {
      expect(
        percentageReduction(baseline: 200, comparison: 150),
        closeTo(25, 0.0001),
      );
    });

    test('calcula redução percentual negativa quando comparison é maior', () {
      expect(
        percentageReduction(baseline: 100, comparison: 150),
        closeTo(-50, 0.0001),
      );
    });

    test('lança quando baseline é zero', () {
      expect(
        () => percentageReduction(baseline: 0, comparison: 10),
        throwsArgumentError,
      );
    });
  });
}
