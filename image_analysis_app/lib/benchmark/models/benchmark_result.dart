import '../config/experiment_config.dart';

/// Resultado de uma única execução de tarefa; os campos correspondem
/// diretamente às colunas do CSV exportado.
///
/// Os campos de medição são anuláveis: quando a tarefa falha antes de uma
/// etapa ser concluída (ex.: download falhou, então não há
/// `downloadTimeUs`/`receivedSizeBytes` confiáveis), o campo correspondente
/// fica `null` em vez de `0` — uma falha nunca deve virar zero, já que `0`
/// seria indistinguível de uma medição real. [error] identifica a falha;
/// [isError] é `true` sempre que há algum campo de medição ausente.
class BenchmarkResult {
  const BenchmarkResult({
    required this.experimentId,
    required this.runId,
    required this.sequenceIndex,
    required this.variantId,
    required this.sourceImageId,
    required this.repetition,
    required this.format,
    required this.quality,
    required this.resolutionProfile,
    required this.deviceLabel,
    required this.flutterVersion,
    required this.operatingSystemVersion,
    required this.serverBaseUrl,
    required this.timestamp,
    this.receivedSizeBytes,
    this.downloadTimeUs,
    this.decodeTimeUs,
    this.totalLoadTimeUs,
    this.decodedWidth,
    this.decodedHeight,
    this.decodedMemoryEstimatedBytes,
    this.ssim,
    this.httpStatusCode,
    this.error,
  });

  final String experimentId;
  final String runId;
  final int sequenceIndex;
  final String variantId;
  final String sourceImageId;
  final int repetition;
  final ImageFormat format;
  final int quality;
  final ResolutionProfile resolutionProfile;
  final int? receivedSizeBytes;
  final int? downloadTimeUs;
  final int? decodeTimeUs;
  final int? totalLoadTimeUs;
  final int? decodedWidth;
  final int? decodedHeight;
  final int? decodedMemoryEstimatedBytes;
  final double? ssim;
  final String deviceLabel;
  final String flutterVersion;
  final String operatingSystemVersion;
  final String serverBaseUrl;
  final DateTime timestamp;
  final int? httpStatusCode;
  final String? error;

  bool get isError => error != null;
}
