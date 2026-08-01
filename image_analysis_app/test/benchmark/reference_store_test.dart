import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/data/reference_store.dart';
import 'package:image_analysis_app/benchmark/models/experiment_manifest.dart';
import 'package:image_analysis_app/benchmark/models/image_variant.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  var referenceRequestCount = 0;

  setUp(() async {
    referenceRequestCount = 0;
    server = await HttpServer.bind('127.0.0.1', 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
    server.listen((request) async {
      if (request.uri.path.startsWith('/references/')) {
        referenceRequestCount++;
        final id = request.uri.path.split('/').last;
        request.response.statusCode = 200;
        request.response.add(utf8.encode('referencia-$id'));
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  ExperimentManifest manifestWithTwoImages() {
    final variants = <ImageVariant>[];
    for (final imageId in <String>['image_001', 'image_002']) {
      variants.add(ImageVariant(
        variantId: '${imageId}__original__jpeg__q70',
        sourceImageId: imageId,
        relativeUrl: 'variants/${imageId}__original__jpeg__q70.jpg',
        referenceUrl: 'references/${imageId}__reference1080.png',
        format: ImageFormat.jpeg,
        quality: 70,
        resolutionProfile: ResolutionProfile.original,
        manifestSizeBytes: 100,
        expectedWidth: 1080,
        expectedHeight: 720,
      ));
      // Uma segunda variante da mesma imagem, para garantir que a
      // referência é buscada uma única vez por sourceImageId.
      variants.add(ImageVariant(
        variantId: '${imageId}__target1080__webp__q85',
        sourceImageId: imageId,
        relativeUrl: 'variants/${imageId}__target1080__webp__q85.webp',
        referenceUrl: 'references/${imageId}__reference1080.png',
        format: ImageFormat.webp,
        quality: 85,
        resolutionProfile: ResolutionProfile.target1080,
        manifestSizeBytes: 90,
        expectedWidth: 1080,
        expectedHeight: 720,
      ));
    }

    return ExperimentManifest(
      schemaVersion: 1,
      datasetId: 'photo-benchmark-v1',
      generatedAt: DateTime.utc(2026, 7, 24),
      sourceImageCount: 2,
      variantCount: variants.length,
      repetitionsPerVariant: 3,
      resizeAlgorithm: 'linear',
      encoders: const <String, String>{},
      variants: variants,
    );
  }

  test('carrega uma referência por sourceImageId, sem duplicar requisições', () async {
    final store = ReferenceStore();
    await store.loadAll(baseUri, manifestWithTwoImages());

    expect(store.loadedCount, 2);
    expect(referenceRequestCount, 2);
    expect(
      utf8.decode(store.referenceFor('image_001')),
      'referencia-image_001__reference1080.png',
    );
    expect(
      utf8.decode(store.referenceFor('image_002')),
      'referencia-image_002__reference1080.png',
    );
    store.close();
  });

  test('lança ReferenceLoadException para sourceImageId desconhecido', () async {
    final store = ReferenceStore();
    await store.loadAll(baseUri, manifestWithTwoImages());
    expect(
      () => store.referenceFor('image_999'),
      throwsA(isA<ReferenceLoadException>()),
    );
    store.close();
  });
}
