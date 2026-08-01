import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/models/experiment_manifest.dart';
import 'package:image_analysis_app/benchmark/models/image_variant.dart';

void main() {
  group('ImageVariant', () {
    test('round-trips through JSON', () {
      const variant = ImageVariant(
        variantId: 'image_001__target1080__webp__q85',
        sourceImageId: 'image_001',
        relativeUrl: 'variants/image_001__target1080__webp__q85.webp',
        referenceUrl: 'references/image_001__reference1080.png',
        format: ImageFormat.webp,
        quality: 85,
        resolutionProfile: ResolutionProfile.target1080,
        manifestSizeBytes: 123456,
        expectedWidth: 1080,
        expectedHeight: 720,
      );

      final decoded = ImageVariant.fromJson(variant.toJson());

      expect(decoded.variantId, variant.variantId);
      expect(decoded.sourceImageId, variant.sourceImageId);
      expect(decoded.relativeUrl, variant.relativeUrl);
      expect(decoded.referenceUrl, variant.referenceUrl);
      expect(decoded.format, ImageFormat.webp);
      expect(decoded.quality, 85);
      expect(decoded.resolutionProfile, ResolutionProfile.target1080);
      expect(decoded.manifestSizeBytes, 123456);
      expect(decoded.expectedWidth, 1080);
      expect(decoded.expectedHeight, 720);
    });

    test('rejects unknown format value', () {
      expect(
        () => ImageFormat.fromWireValue('png'),
        throwsFormatException,
      );
    });

    test('rejects unknown resolution profile value', () {
      expect(
        () => ResolutionProfile.fromWireValue('4k'),
        throwsFormatException,
      );
    });
  });

  group('ExperimentManifest', () {
    test('round-trips through JSON', () {
      final manifest = ExperimentManifest(
        schemaVersion: 1,
        datasetId: 'photo-benchmark-v1',
        generatedAt: DateTime.utc(2026, 7, 24, 12),
        sourceImageCount: 1,
        variantCount: 1,
        repetitionsPerVariant: 3,
        resizeAlgorithm: 'linear',
        encoders: const <String, String>{
          'jpeg': 'package:image 4.9.1',
          'webp': 'cwebp 1.6.0',
        },
        variants: const <ImageVariant>[
          ImageVariant(
            variantId: 'image_001__original__jpeg__q70',
            sourceImageId: 'image_001',
            relativeUrl: 'variants/image_001__original__jpeg__q70.jpg',
            referenceUrl: 'references/image_001__reference1080.png',
            format: ImageFormat.jpeg,
            quality: 70,
            resolutionProfile: ResolutionProfile.original,
            manifestSizeBytes: 442237,
            expectedWidth: 2048,
            expectedHeight: 1365,
          ),
        ],
      );

      final decoded = ExperimentManifest.fromJson(manifest.toJson());

      expect(decoded.schemaVersion, 1);
      expect(decoded.datasetId, 'photo-benchmark-v1');
      expect(decoded.generatedAt, manifest.generatedAt);
      expect(decoded.sourceImageCount, 1);
      expect(decoded.variantCount, 1);
      expect(decoded.repetitionsPerVariant, 3);
      expect(decoded.resizeAlgorithm, 'linear');
      expect(decoded.encoders, manifest.encoders);
      expect(decoded.variants, hasLength(1));
      expect(decoded.variants.single.variantId,
          'image_001__original__jpeg__q70');
    });
  });
}
