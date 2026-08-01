/// Constantes e enums centrais do experimento.
library;

enum ImageFormat {
  jpeg,
  webp;

  static ImageFormat fromWireValue(String value) {
    return ImageFormat.values.firstWhere(
      (format) => format.wireValue == value,
      orElse: () => throw FormatException('Formato desconhecido: $value'),
    );
  }

  String get wireValue => switch (this) {
    ImageFormat.jpeg => 'jpeg',
    ImageFormat.webp => 'webp',
  };
}

enum ResolutionProfile {
  original,
  target1080;

  static ResolutionProfile fromWireValue(String value) {
    return ResolutionProfile.values.firstWhere(
      (profile) => profile.wireValue == value,
      orElse: () => throw FormatException('Perfil de resolução '
          'desconhecido: $value'),
    );
  }

  String get wireValue => switch (this) {
    ResolutionProfile.original => 'original',
    ResolutionProfile.target1080 => 'target1080',
  };
}

const List<int> qualityLevels = <int>[70, 85, 95];

/// Lado maior alvo do perfil `target1080`, em pixels físicos.
///
/// **Justificativa concreta:** 1080 corresponde à largura física de tela
/// da classe "FHD+" (ex.: 1080×2340, 1080×2400), a faixa de resolução mais
/// comum entre aparelhos Android de entrada e intermediários. Um app que
/// exibe a fotografia em largura total (`largura lógica do widget ≈
/// largura lógica da tela`) nesses aparelhos precisa de, no máximo,
/// `larguraLógica × densidadeDeTela` pixels físicos — que caem perto de
/// 1080 nessa classe de dispositivo (ex.: ~360dp × 3.0 ≈ 1080px).
///
/// **Isto NÃO é uma recomendação universal.** Aparelhos com largura física
/// maior (classe "QHD+", 1440px+) exigiriam um valor maior para exibir a
/// foto em resolução nativa sem upscaling; para eles, `target1080`
/// representa uma redução deliberada, não o tamanho "ideal" de exibição.
/// Trate `target1080` como um perfil experimental que representa um
/// cenário concreto e comum (tela FHD+), não como o tamanho recomendado
/// para qualquer app Flutter.
const int targetLongestSidePx = 1080;

/// Mesmo valor de [targetLongestSidePx]: a referência de SSIM usa o mesmo
/// lado maior para que a comparação ocorra na mesma resolução do perfil
/// `target1080` (ver `../dataset/bin/prepare_dataset.dart`).
const int comparisonLongestSidePx = 1080;

const int repetitionsPerVariant = 3;

/// Estrutural (2 formatos × 3 qualidades × 2 resoluções), não depende da
/// quantidade de imagens do dataset — por isso é a única contagem
/// "fechada" aqui. A quantidade de imagens e de variantes totais vem do
/// `manifest.json` em tempo de execução (ver `ManifestLoader` e
/// `BenchmarkProgress.totalTasks`): quem gera o dataset (`dataset/bin/
/// select_images.dart --count`) escolhe livremente o tamanho, sem precisar
/// tocar neste arquivo.
const int variantsPerImage = 12;
const Duration intervalBetweenTasks = Duration(milliseconds: 250);

/// Regra de falhas, definida a priori (ver README, seção "Regra de
/// falhas"): cada tarefa é tentada até [maxAttemptsPerTask] vezes (nova
/// requisição HTTP, novo `runId`, mesmo `repetition`/`sequenceIndex`)
/// antes de ser registrada como falha definitiva. Apenas o resultado da
/// última tentativa é persistido no CSV — tentativas anteriores que
/// falharam são registradas apenas no log do console, não em colunas
/// adicionais do CSV.
const int maxAttemptsPerTask = 3;

/// Espera entre tentativas de uma mesma tarefa (distinta do intervalo
/// fixo entre tarefas diferentes, [intervalBetweenTasks]).
const Duration retryBackoff = Duration(milliseconds: 500);

/// Versão do Flutter usada para construir o app, registrada nos resultados
/// para fins de reprodutibilidade. Sem API de runtime para consultar isso
/// automaticamente; atualizar manualmente ao trocar de SDK
/// (`flutter --version`).
const String flutterVersionForRecordKeeping = '3.44.7';

