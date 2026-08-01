import '../config/experiment_config.dart';

/// Uma variante codificada de uma imagem-fonte, conforme entrada do
/// `manifest.json` gerado pelo preparador de dataset.
class ImageVariant {
  const ImageVariant({
    required this.variantId,
    required this.sourceImageId,
    required this.relativeUrl,
    required this.referenceUrl,
    required this.format,
    required this.quality,
    required this.resolutionProfile,
    required this.manifestSizeBytes,
    required this.expectedWidth,
    required this.expectedHeight,
  });

  factory ImageVariant.fromJson(Map<String, dynamic> json) {
    return ImageVariant(
      variantId: json['variantId'] as String,
      sourceImageId: json['sourceImageId'] as String,
      relativeUrl: json['relativeUrl'] as String,
      referenceUrl: json['referenceUrl'] as String,
      format: ImageFormat.fromWireValue(json['format'] as String),
      quality: json['quality'] as int,
      resolutionProfile: ResolutionProfile.fromWireValue(
        json['resolutionProfile'] as String,
      ),
      manifestSizeBytes: json['encodedSizeBytes'] as int,
      expectedWidth: json['width'] as int,
      expectedHeight: json['height'] as int,
    );
  }

  final String variantId;
  final String sourceImageId;
  final String relativeUrl;
  final String referenceUrl;
  final ImageFormat format;
  final int quality;
  final ResolutionProfile resolutionProfile;
  final int manifestSizeBytes;
  final int expectedWidth;
  final int expectedHeight;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'variantId': variantId,
    'sourceImageId': sourceImageId,
    'relativeUrl': relativeUrl,
    'referenceUrl': referenceUrl,
    'format': format.wireValue,
    'quality': quality,
    'resolutionProfile': resolutionProfile.wireValue,
    'encodedSizeBytes': manifestSizeBytes,
    'width': expectedWidth,
    'height': expectedHeight,
  };
}
