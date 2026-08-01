import 'dart:io';

import '../models/benchmark_result.dart';

/// Colunas do CSV exportado, nesta ordem fixa.
const List<String> csvColumns = <String>[
  'experiment_id',
  'run_id',
  'sequence_index',
  'variant_id',
  'source_image_id',
  'repetition',
  'format',
  'quality',
  'resolution_profile',
  'received_size_bytes',
  'download_time_us',
  'decode_time_us',
  'total_load_time_us',
  'decoded_width',
  'decoded_height',
  'decoded_memory_estimated_bytes',
  'ssim',
  'device_label',
  'flutter_version',
  'operating_system_version',
  'server_base_url',
  'http_status_code',
  'error',
  'timestamp',
];

String escapeCsvField(String value) {
  final needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

String encodeCsvRow(List<String> fields) {
  return fields.map(escapeCsvField).join(',');
}

List<String> csvRowFor(BenchmarkResult result) {
  return <String>[
    result.experimentId,
    result.runId,
    result.sequenceIndex.toString(),
    result.variantId,
    result.sourceImageId,
    result.repetition.toString(),
    result.format.wireValue,
    result.quality.toString(),
    result.resolutionProfile.wireValue,
    result.receivedSizeBytes?.toString() ?? '',
    result.downloadTimeUs?.toString() ?? '',
    result.decodeTimeUs?.toString() ?? '',
    result.totalLoadTimeUs?.toString() ?? '',
    result.decodedWidth?.toString() ?? '',
    result.decodedHeight?.toString() ?? '',
    result.decodedMemoryEstimatedBytes?.toString() ?? '',
    result.ssim?.toString() ?? '',
    result.deviceLabel,
    result.flutterVersion,
    result.operatingSystemVersion,
    result.serverBaseUrl,
    result.httpStatusCode?.toString() ?? '',
    result.error ?? '',
    result.timestamp.toUtc().toIso8601String(),
  ];
}

/// Escreve resultados em CSV incrementalmente: cabeçalho uma única vez,
/// `flush` após cada linha, e reabertura segura em modo `append` (o
/// cabeçalho só é escrito se o arquivo ainda não existir ou estiver vazio,
/// permitindo retomar uma rodada sem duplicá-lo).
///
/// A deduplicação de tarefas já registradas antes de uma retomada é
/// responsabilidade do runner (que pode ler o CSV existente antes de
/// recriar a lista de tarefas pendentes); este exportador apenas garante
/// que cada chamada a [appendResult] produz exatamente uma linha.
class CsvExporter {
  CsvExporter(this.file);

  final File file;
  IOSink? _sink;

  Future<void> open() async {
    final exists = await file.exists();
    final hasContent = exists && await file.length() > 0;

    if (!exists) {
      await file.create(recursive: true);
    }

    _sink = file.openWrite(mode: FileMode.append);

    if (!hasContent) {
      _sink!.writeln(encodeCsvRow(csvColumns));
      await _sink!.flush();
    }
  }

  Future<void> appendResult(BenchmarkResult result) async {
    final sink = _sink;
    if (sink == null) {
      throw StateError('CsvExporter.open() precisa ser chamado antes de '
          'appendResult()');
    }
    sink.writeln(encodeCsvRow(csvRowFor(result)));
    await sink.flush();
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
