import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/data/manifest_loader.dart';

Map<String, dynamic> _variant({
  required String sourceImageId,
  required String format,
  required int quality,
  required String resolutionProfile,
  String? relativeUrl,
  String? referenceUrl,
  int encodedSizeBytes = 1000,
  int width = 1080,
  int height = 720,
}) {
  final variantId =
      '${sourceImageId}__${resolutionProfile}__${format}__q$quality';
  final extension = format == 'jpeg' ? 'jpg' : 'webp';
  return <String, dynamic>{
    'variantId': variantId,
    'sourceImageId': sourceImageId,
    'relativeUrl': relativeUrl ?? 'variants/$variantId.$extension',
    'referenceUrl':
        referenceUrl ?? 'references/${sourceImageId}__reference1080.png',
    'format': format,
    'quality': quality,
    'resolutionProfile': resolutionProfile,
    'encodedSizeBytes': encodedSizeBytes,
    'width': width,
    'height': height,
  };
}

List<Map<String, dynamic>> _twelveVariantsFor(String sourceImageId) {
  final variants = <Map<String, dynamic>>[];
  for (final profile in <String>['original', 'target1080']) {
    for (final format in <String>['jpeg', 'webp']) {
      for (final quality in <int>[70, 85, 95]) {
        variants.add(_variant(
          sourceImageId: sourceImageId,
          format: format,
          quality: quality,
          resolutionProfile: profile,
        ));
      }
    }
  }
  return variants;
}

Map<String, dynamic> _validManifest({List<Map<String, dynamic>>? variants}) {
  final resolvedVariants = variants ?? _twelveVariantsFor('image_001');
  return <String, dynamic>{
    'schemaVersion': 1,
    'datasetId': 'photo-benchmark-v1',
    'generatedAt': '2026-07-24T12:00:00Z',
    'sourceImageCount': 1,
    'variantCount': resolvedVariants.length,
    'repetitionsPerVariant': 3,
    'resizeAlgorithm': 'linear',
    'encoders': <String, String>{'jpeg': 'image 4.9.1', 'webp': 'cwebp 1.6.0'},
    'variants': resolvedVariants,
  };
}

void main() {
  test('aceita um manifesto válido com 12 variantes por imagem', () {
    final manifest = parseAndValidate(jsonEncode(_validManifest()));
    expect(manifest.variants, hasLength(12));
  });

  test('rejeita quando variantCount não bate com a lista', () {
    final json = _validManifest();
    json['variantCount'] = 999;
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita variantId duplicado', () {
    final variants = _twelveVariantsFor('image_001');
    variants.add(variants.first);
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita qualidade fora da lista permitida', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 42,
      resolutionProfile: 'original',
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita relativeUrl com travessia de diretório', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 70,
      resolutionProfile: 'original',
      relativeUrl: '../../etc/passwd',
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita relativeUrl absoluto', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 70,
      resolutionProfile: 'original',
      relativeUrl: '/variants/x.jpg',
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita tamanho não positivo', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 70,
      resolutionProfile: 'original',
      encodedSizeBytes: 0,
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita dimensões não positivas', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 70,
      resolutionProfile: 'original',
      width: 0,
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita imagem-fonte com número de variantes diferente de 12', () {
    final variants = _twelveVariantsFor('image_001')..removeLast();
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita referência de SSIM inconsistente para a mesma imagem', () {
    final variants = _twelveVariantsFor('image_001');
    variants[0] = _variant(
      sourceImageId: 'image_001',
      format: 'jpeg',
      quality: 70,
      resolutionProfile: 'original',
      referenceUrl: 'references/outra_referencia.png',
    );
    final json = _validManifest(variants: variants);
    expect(
      () => parseAndValidate(jsonEncode(json)),
      throwsA(isA<ManifestValidationException>()),
    );
  });

  test('rejeita JSON malformado', () {
    expect(
      () => parseAndValidate('{not valid json'),
      throwsA(isA<ManifestValidationException>()),
    );
  });
}
