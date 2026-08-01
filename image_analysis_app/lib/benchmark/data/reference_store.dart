import 'dart:io';
import 'dart:typed_data';

import '../models/experiment_manifest.dart';

class ReferenceLoadException implements Exception {
  ReferenceLoadException(this.message);
  final String message;

  @override
  String toString() => 'ReferenceLoadException: $message';
}

/// Carrega e mantém em memória as referências de SSIM (uma por
/// `sourceImageId`, quantidade determinada pelo `manifest.json` da rodada)
/// antes do início das tarefas, fora dos cronômetros de benchmark.
class ReferenceStore {
  ReferenceStore({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final Map<String, Uint8List> _referencesBySourceImageId =
      <String, Uint8List>{};

  Future<void> loadAll(Uri baseUri, ExperimentManifest manifest) async {
    final referenceUrlBySourceImageId = <String, String>{};
    for (final variant in manifest.variants) {
      referenceUrlBySourceImageId.putIfAbsent(
        variant.sourceImageId,
        () => variant.referenceUrl,
      );
    }

    for (final entry in referenceUrlBySourceImageId.entries) {
      final uri = baseUri.resolve(entry.value);
      _referencesBySourceImageId[entry.key] = await _fetch(uri);
    }
  }

  Uint8List referenceFor(String sourceImageId) {
    final bytes = _referencesBySourceImageId[sourceImageId];
    if (bytes == null) {
      throw ReferenceLoadException(
        'Referência de SSIM ausente para $sourceImageId',
      );
    }
    return bytes;
  }

  int get loadedCount => _referencesBySourceImageId.length;

  Future<Uint8List> _fetch(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ReferenceLoadException(
          'Status HTTP ${response.statusCode} ao buscar referência $uri',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on ReferenceLoadException {
      rethrow;
    } on Exception catch (e) {
      throw ReferenceLoadException('Falha ao buscar referência $uri: $e');
    }
  }

  void close() => _httpClient.close(force: true);
}
