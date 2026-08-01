/// Metadados do ambiente de execução, registrados junto a cada resultado
/// para permitir reprodutibilidade e comparação entre dispositivos. A
/// coleta real (via `device_info_plus`) acontece em
/// `data/device_info_provider.dart`; esta classe é um contêiner de dados
/// simples e testável sem plugins de plataforma.
class DeviceEnvironment {
  const DeviceEnvironment({
    required this.deviceLabel,
    required this.manufacturer,
    required this.model,
    required this.operatingSystemVersion,
    required this.flutterVersion,
    required this.dartVersion,
  });

  /// Rótulo curto e legível usado em `BenchmarkResult.deviceLabel` e nos
  /// filtros da tela de resultados, ex. "Pixel 6 (Android 14)".
  final String deviceLabel;
  final String manufacturer;
  final String model;
  final String operatingSystemVersion;
  final String flutterVersion;
  final String dartVersion;

  static String buildLabel({
    required String model,
    required String operatingSystemVersion,
  }) {
    return '$model ($operatingSystemVersion)';
  }
}
