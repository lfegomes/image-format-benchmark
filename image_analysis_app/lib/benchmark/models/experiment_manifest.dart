import 'image_variant.dart';

/// Manifesto gerado pelo preparador de dataset. A validação de
/// consistência (contagens, IDs únicos, etc.) fica em
/// `data/manifest_loader.dart`.
class ExperimentManifest {
  const ExperimentManifest({
    required this.schemaVersion,
    required this.datasetId,
    required this.generatedAt,
    required this.sourceImageCount,
    required this.variantCount,
    required this.repetitionsPerVariant,
    required this.resizeAlgorithm,
    required this.encoders,
    required this.variants,
  });

  factory ExperimentManifest.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'] as List<dynamic>;
    return ExperimentManifest(
      schemaVersion: json['schemaVersion'] as int,
      datasetId: json['datasetId'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      sourceImageCount: json['sourceImageCount'] as int,
      variantCount: json['variantCount'] as int,
      repetitionsPerVariant: json['repetitionsPerVariant'] as int,
      resizeAlgorithm: json['resizeAlgorithm'] as String,
      encoders: Map<String, String>.from(
        json['encoders'] as Map<dynamic, dynamic>,
      ),
      variants: rawVariants
          .map((entry) => ImageVariant.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int schemaVersion;
  final String datasetId;
  final DateTime generatedAt;
  final int sourceImageCount;
  final int variantCount;
  final int repetitionsPerVariant;
  final String resizeAlgorithm;
  final Map<String, String> encoders;
  final List<ImageVariant> variants;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'datasetId': datasetId,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'sourceImageCount': sourceImageCount,
    'variantCount': variantCount,
    'repetitionsPerVariant': repetitionsPerVariant,
    'resizeAlgorithm': resizeAlgorithm,
    'encoders': encoders,
    'variants': variants.map((variant) => variant.toJson()).toList(),
  };
}
