import 'package:flutter_test/flutter_test.dart';

import 'package:image_analysis_app/app.dart';

void main() {
  testWidgets('a tela de configuração é a tela inicial e renderiza os '
      'campos principais', (WidgetTester tester) async {
    await tester.pumpWidget(const BenchmarkApp());
    await tester.pump();

    expect(find.text('Benchmark de imagens — configuração'), findsOneWidget);
    expect(find.text('Testar conexão'), findsOneWidget);
    expect(find.text('Carregar manifesto'), findsOneWidget);
    expect(find.text('Executar experimento'), findsOneWidget);
  });
}
