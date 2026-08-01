import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/prepare_dataset.dart';

void main() {
  late Directory tempRoot;
  late Directory sourceDir;
  late Directory outputDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('prepare_dataset_test_');
    sourceDir = Directory(p.join(tempRoot.path, 'source'))
      ..createSync(recursive: true);
    outputDir = Directory(p.join(tempRoot.path, 'generated'));

    for (final imageId in <String>['image_001', 'image_002']) {
      final synthetic = img.Image(width: 1400, height: 900);
      img.fill(synthetic, color: img.ColorRgb8(90, 140, 200));
      img.drawRect(
        synthetic,
        x1: 100,
        y1: 100,
        x2: 900,
        y2: 600,
        color: img.ColorRgb8(220, 60, 30),
      );
      File(p.join(sourceDir.path, '$imageId.png'))
          .writeAsBytesSync(img.encodePng(synthetic));
    }
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  test('gera 12 variantes por imagem e uma referência por imagem', () async {
    final cwebpPath = p.join(Directory.current.path, 'bin', 'cwebp');
    expect(File(cwebpPath).existsSync(), isTrue,
        reason: 'cwebp precisa existir em bin/cwebp para este teste');

    final options = PrepareDatasetOptions.parse(<String>[]);
    final testOptions = _withPaths(
      options,
      sourceDirPath: sourceDir.path,
      outputDirPath: outputDir.path,
      cwebpPath: cwebpPath,
      tempDirPath: p.join(tempRoot.path, 'tmp'),
      expectedImageCount: 2,
    );

    final manifest = await generateManifest(testOptions);

    final variants = manifest['variants'] as List<dynamic>;
    expect(manifest['sourceImageCount'], 2);
    expect(variants, hasLength(2 * variantsPerImage));

    for (final imageId in <String>['image_001', 'image_002']) {
      final variantsForImage = variants
          .cast<Map<String, dynamic>>()
          .where((v) => v['sourceImageId'] == imageId);
      expect(variantsForImage, hasLength(variantsPerImage));

      final formats = variantsForImage.map((v) => v['format']).toSet();
      expect(formats, <String>{'jpeg', 'webp'});

      final profiles =
          variantsForImage.map((v) => v['resolutionProfile']).toSet();
      expect(profiles, <String>{'original', 'target1080'});

      final qualities =
          variantsForImage.map((v) => v['quality']).toSet();
      expect(qualities, <int>{70, 85, 95});

      for (final variant in variantsForImage) {
        final relativeUrl = variant['relativeUrl'] as String;
        final file = File(p.join(outputDir.path, relativeUrl));
        expect(file.existsSync(), isTrue,
            reason: 'arquivo da variante $relativeUrl deveria existir');
        expect(file.lengthSync(), variant['encodedSizeBytes']);
      }

      final referenceFile = File(
        p.join(outputDir.path, 'references', '${imageId}__reference1080.png'),
      );
      expect(referenceFile.existsSync(), isTrue);
    }
  });

  test('falha explicitamente quando cwebp não é encontrado', () async {
    final options = PrepareDatasetOptions.parse(<String>[]);
    final testOptions = _withPaths(
      options,
      sourceDirPath: sourceDir.path,
      outputDirPath: outputDir.path,
      cwebpPath: p.join(tempRoot.path, 'cwebp-inexistente'),
      tempDirPath: p.join(tempRoot.path, 'tmp'),
      expectedImageCount: 2,
    );

    expect(
      () => generateManifest(testOptions),
      throwsA(isA<ProcessException>()),
    );
  });
}

PrepareDatasetOptions _withPaths(
  PrepareDatasetOptions base, {
  required String sourceDirPath,
  required String outputDirPath,
  required String cwebpPath,
  required String tempDirPath,
  required int? expectedImageCount,
}) {
  return PrepareDatasetOptions(
    sourceDirPath: sourceDirPath,
    outputDirPath: outputDirPath,
    cwebpPath: cwebpPath,
    tempDirPath: tempDirPath,
    datasetId: base.datasetId,
    expectedImageCount: expectedImageCount,
  );
}
