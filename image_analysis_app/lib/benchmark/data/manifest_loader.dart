import 'dart:convert';
import 'dart:io';

import '../config/experiment_config.dart';
import '../models/experiment_manifest.dart';
import '../models/image_variant.dart';

class ManifestValidationException implements Exception {
  ManifestValidationException(this.message);
  final String message;

  @override
  String toString() => 'ManifestValidationException: $message';
}

class ManifestFetchException implements Exception {
  ManifestFetchException(this.message, {this.httpStatusCode});
  final String message;
  final int? httpStatusCode;

  @override
  String toString() => 'ManifestFetchException: $message';
}

/// Baixa e valida `manifest.json` a partir da URL-base do servidor.
class ManifestLoader {
  ManifestLoader({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<ExperimentManifest> fetchAndValidate(Uri baseUri) async {
    final manifestUri = baseUri.resolve('manifest.json');
    String rawBody;
    try {
      final request = await _httpClient.getUrl(manifestUri);
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, must-revalidate',
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw ManifestFetchException(
          'Status HTTP inesperado ao buscar manifest.json: '
          '${response.statusCode}',
          httpStatusCode: response.statusCode,
        );
      }
      rawBody = await response.transform(utf8.decoder).join();
    } on ManifestFetchException {
      rethrow;
    } on Exception catch (e) {
      throw ManifestFetchException('Falha ao buscar manifest.json: $e');
    }

    return parseAndValidate(rawBody);
  }

  void close() => _httpClient.close(force: true);
}

/// Faz o parse do JSON e valida a consistência do manifesto (contagens,
/// IDs únicos, formatos/qualidades permitidos, caminhos seguros), sem I/O
/// — usado diretamente pelos testes com manifestos sintéticos.
ExperimentManifest parseAndValidate(String rawJson) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(rawJson) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw ManifestValidationException('JSON inválido: $e');
  }

  final ExperimentManifest manifest;
  try {
    manifest = ExperimentManifest.fromJson(json);
  } on Exception catch (e) {
    throw ManifestValidationException('Estrutura de manifesto inválida: $e');
  }

  validateManifest(manifest);
  return manifest;
}

void validateManifest(ExperimentManifest manifest) {
  if (manifest.variants.length != manifest.variantCount) {
    throw ManifestValidationException(
      'variantCount (${manifest.variantCount}) não corresponde ao tamanho '
      'da lista de variantes (${manifest.variants.length})',
    );
  }

  final seenIds = <String>{};
  for (final variant in manifest.variants) {
    if (!seenIds.add(variant.variantId)) {
      throw ManifestValidationException(
        'variantId duplicado: ${variant.variantId}',
      );
    }
  }

  for (final variant in manifest.variants) {
    if (!qualityLevels.contains(variant.quality)) {
      throw ManifestValidationException(
        'Qualidade não permitida em ${variant.variantId}: '
        '${variant.quality}',
      );
    }
    _validateRelativePath(variant.variantId, 'relativeUrl', variant.relativeUrl);
    _validateRelativePath(
      variant.variantId,
      'referenceUrl',
      variant.referenceUrl,
    );
    if (variant.manifestSizeBytes <= 0) {
      throw ManifestValidationException(
        'encodedSizeBytes inválido em ${variant.variantId}',
      );
    }
    if (variant.expectedWidth <= 0 || variant.expectedHeight <= 0) {
      throw ManifestValidationException(
        'Dimensões inválidas em ${variant.variantId}',
      );
    }
  }

  final variantsBySourceImage = <String, List<ImageVariant>>{};
  for (final variant in manifest.variants) {
    variantsBySourceImage
        .putIfAbsent(variant.sourceImageId, () => <ImageVariant>[])
        .add(variant);
  }

  for (final entry in variantsBySourceImage.entries) {
    if (entry.value.length != variantsPerImage) {
      throw ManifestValidationException(
        '${entry.key} tem ${entry.value.length} variantes, esperava '
        '$variantsPerImage',
      );
    }
    final referenceUrls = entry.value.map((v) => v.referenceUrl).toSet();
    if (referenceUrls.length != 1) {
      throw ManifestValidationException(
        '${entry.key} referencia mais de uma referência de SSIM: '
        '$referenceUrls',
      );
    }
  }
}

void _validateRelativePath(String variantId, String field, String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains('..')) {
    throw ManifestValidationException(
      '$field inseguro ou inválido em $variantId: $value',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.isAbsolute) {
    throw ManifestValidationException(
      '$field deve ser um caminho relativo em $variantId: $value',
    );
  }
}
