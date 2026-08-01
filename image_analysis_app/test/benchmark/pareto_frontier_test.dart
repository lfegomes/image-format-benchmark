import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/stats/pareto_frontier.dart';

void main() {
  test('remove pontos estritamente dominados', () {
    final points = <ParetoPoint<String>>[
      const ParetoPoint(item: 'A', sizeBytes: 100, ssim: 0.9),
      const ParetoPoint(item: 'B', sizeBytes: 150, ssim: 0.85), // dominado por A
      const ParetoPoint(item: 'C', sizeBytes: 80, ssim: 0.8),
      const ParetoPoint(item: 'D', sizeBytes: 120, ssim: 0.95),
    ];

    final frontier = paretoFrontier(points).map((p) => p.item).toSet();

    expect(frontier, <String>{'A', 'C', 'D'});
    expect(frontier.contains('B'), isFalse);
  });

  test('mantém pontos empatados (nenhum estritamente melhor)', () {
    final points = <ParetoPoint<String>>[
      const ParetoPoint(item: 'A', sizeBytes: 100, ssim: 0.9),
      const ParetoPoint(item: 'B', sizeBytes: 100, ssim: 0.9),
    ];

    final frontier = paretoFrontier(points).map((p) => p.item).toSet();

    expect(frontier, <String>{'A', 'B'});
  });

  test('lista vazia retorna fronteira vazia', () {
    expect(paretoFrontier(<ParetoPoint<String>>[]), isEmpty);
  });

  test('um único ponto sempre está na fronteira', () {
    final points = <ParetoPoint<String>>[
      const ParetoPoint(item: 'A', sizeBytes: 100, ssim: 0.9),
    ];
    expect(paretoFrontier(points).map((p) => p.item), <String>['A']);
  });
}
