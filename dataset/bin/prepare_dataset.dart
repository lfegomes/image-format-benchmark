// Preparador de dataset: gera as 12 variantes (2 formatos × 3 qualidades ×
// 2 resoluções) de cada uma das imagens-fonte, mais uma referência
// normalizada de 1080px por imagem para SSIM, e escreve manifest.json.
// Ver dataset/README.md.
//
// Uso (a partir da raiz do pacote `dataset/`):
//   dart run bin/prepare_dataset.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

const String preparerScriptVersion = '1.0.0';
const String defaultDatasetId = 'photo-benchmark-v1';
const String resizeAlgorithmName = 'linear';

// Constantes do experimento. Este pacote é autônomo (não depende de
// image_analysis_app), então os valores abaixo são intencionalmente
// duplicados de image_analysis_app/lib/benchmark/config/
// experiment_config.dart — mantenha os dois em sincronia se os parâmetros
// do experimento (qualidades, resolução-alvo, repetições) mudarem.
//
// A quantidade de imagens do dataset NÃO é uma dessas constantes: ela é
// decidida em tempo de execução por quem roda select_images.dart --count,
// e este script deriva a contagem esperada de selected_images.txt (ver
// _expectedCountFromSelection). Isso permite que qualquer pessoa que
// clone o repositório escolha livremente o tamanho do dataset, sem editar
// código em nenhum dos dois pacotes.
const List<int> qualityLevels = <int>[70, 85, 95];
const int targetLongestSidePx = 1080;
const int repetitionsPerVariant = 3;
const int variantsPerImage = 12;

enum ResolutionProfile {
  original('original'),
  target1080('target1080');

  const ResolutionProfile(this.wireValue);
  final String wireValue;
}

Future<void> main(List<String> arguments) async {
  final options = PrepareDatasetOptions.parse(arguments);

  final cwebpFile = File(options.cwebpPath);
  if (!cwebpFile.existsSync()) {
    stderr.writeln('cwebp não encontrado em: ${options.cwebpPath}');
    exitCode = 1;
    return;
  }

  final sourceDir = Directory(options.sourceDirPath);
  if (!sourceDir.existsSync()) {
    stderr.writeln('Diretório de imagens-fonte não encontrado: '
        '${sourceDir.path}');
    exitCode = 1;
    return;
  }

  final manifest = await generateManifest(options);

  final manifestFile = File('${options.outputDirPath}/manifest.json');
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );

  final variants = manifest['variants'] as List<dynamic>;
  stdout.writeln('');
  stdout.writeln('Manifesto gerado: ${manifestFile.path}');
  stdout.writeln(
    '${variants.length} variantes, ${manifest['sourceImageCount']} '
    'referências.',
  );
  final expectedVariantCount =
      (manifest['sourceImageCount'] as int) * variantsPerImage;
  if (variants.length != expectedVariantCount) {
    stderr.writeln(
      'Aviso: esperava $expectedVariantCount variantes, gerou '
      '${variants.length}.',
    );
  }
}

/// Gera todas as variantes e a referência normalizada para cada imagem em
/// [PrepareDatasetOptions.sourceDirPath], escrevendo os arquivos em
/// [PrepareDatasetOptions.outputDirPath] e retornando o manifesto (ainda não
/// persistido em disco). Extraído como função pública para ser exercitado
/// diretamente pelos testes de integração do preparador.
Future<Map<String, dynamic>> generateManifest(
  PrepareDatasetOptions options,
) async {
  final sourceFiles = Directory(options.sourceDirPath)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));

  final expectedCount = options.expectedImageCount;
  if (expectedCount != null && sourceFiles.length != expectedCount) {
    throw StateError('Esperava $expectedCount imagens-fonte em '
        '${options.sourceDirPath}, encontrou ${sourceFiles.length}.');
  }

  Directory('${options.outputDirPath}/variants').createSync(recursive: true);
  Directory('${options.outputDirPath}/references')
      .createSync(recursive: true);

  final cwebpVersion = await _cwebpVersion(options.cwebpPath);
  final imageVersion = _packageVersionFromLock('image') ?? 'unknown';

  final variants = <Map<String, dynamic>>[];

  for (final sourceFile in sourceFiles) {
    final imageId = _basename(sourceFile.path).replaceAll('.png', '');
    stdout.writeln('Processando $imageId...');

    final bytes = await sourceFile.readAsBytes();
    final original = img.decodePng(bytes);
    if (original == null) {
      throw StateError('Falha ao decodificar ${sourceFile.path}');
    }

    final longestSide = original.width > original.height
        ? original.width
        : original.height;
    if (longestSide <= targetLongestSidePx) {
      throw StateError(
        '$imageId tem lado maior de $longestSide px, que não é maior '
        'que $targetLongestSidePx px; target1080 exige redução real.',
      );
    }

    // A referência de SSIM e o perfil target1080 usam o mesmo redimensiona-
    // mento (mesmo algoritmo, mesmo lado maior de 1080px), então reaproveita-
    // mos o resultado: a referência é a versão lossless dos mesmos pixels
    // usados para gerar as variantes JPEG/WebP de target1080.
    final normalized = _resizeToLongestSide(original, targetLongestSidePx);

    final referenceRelativePath =
        'references/${imageId}__reference1080.png';
    final referenceFile = File(
      '${options.outputDirPath}/$referenceRelativePath',
    );
    await referenceFile.writeAsBytes(img.encodePng(normalized));

    final profiles = <ResolutionProfile, img.Image>{
      ResolutionProfile.original: original,
      ResolutionProfile.target1080: normalized,
    };

    for (final profileEntry in profiles.entries) {
      final profile = profileEntry.key;
      final image = profileEntry.value;

      for (final quality in qualityLevels) {
        final variantId =
            '${imageId}__${profile.wireValue}__jpeg__q$quality';
        final relativeUrl = 'variants/$variantId.jpg';
        final jpegBytes = img.encodeJpg(image, quality: quality);
        await File('${options.outputDirPath}/$relativeUrl')
            .writeAsBytes(jpegBytes);
        variants.add(_variantEntry(
          variantId: variantId,
          sourceImageId: imageId,
          relativeUrl: relativeUrl,
          referenceUrl: referenceRelativePath,
          format: 'jpeg',
          quality: quality,
          profile: profile,
          sizeBytes: jpegBytes.length,
          width: image.width,
          height: image.height,
        ));
      }

      final tempPngPath = profile == ResolutionProfile.original
          ? sourceFile.path
          : await _writeTempPng(image, imageId, options.tempDirPath);
      try {
        for (final quality in qualityLevels) {
          final variantId =
              '${imageId}__${profile.wireValue}__webp__q$quality';
          final relativeUrl = 'variants/$variantId.webp';
          final outputPath = '${options.outputDirPath}/$relativeUrl';
          await _encodeWebpLossy(
            cwebpPath: options.cwebpPath,
            inputPngPath: tempPngPath,
            quality: quality,
            outputPath: outputPath,
          );
          final sizeBytes = await File(outputPath).length();
          variants.add(_variantEntry(
            variantId: variantId,
            sourceImageId: imageId,
            relativeUrl: relativeUrl,
            referenceUrl: referenceRelativePath,
            format: 'webp',
            quality: quality,
            profile: profile,
            sizeBytes: sizeBytes,
            width: image.width,
            height: image.height,
          ));
        }
      } finally {
        if (profile == ResolutionProfile.target1080) {
          final tempFile = File(tempPngPath);
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        }
      }
    }
  }

  return <String, dynamic>{
    'schemaVersion': 1,
    'datasetId': options.datasetId,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceImageCount': sourceFiles.length,
    'variantCount': variants.length,
    'repetitionsPerVariant': repetitionsPerVariant,
    'resizeAlgorithm': resizeAlgorithmName,
    'encoders': <String, String>{
      'jpeg': 'package:image $imageVersion',
      'webp': 'cwebp $cwebpVersion',
    },
    'preparerScriptVersion': preparerScriptVersion,
    'cwebpArgs': '-preset photo -q <quality> <input> -o <output>',
    'variants': variants,
  };
}

Map<String, dynamic> _variantEntry({
  required String variantId,
  required String sourceImageId,
  required String relativeUrl,
  required String referenceUrl,
  required String format,
  required int quality,
  required ResolutionProfile profile,
  required int sizeBytes,
  required int width,
  required int height,
}) {
  return <String, dynamic>{
    'variantId': variantId,
    'sourceImageId': sourceImageId,
    'relativeUrl': relativeUrl,
    'referenceUrl': referenceUrl,
    'format': format,
    'quality': quality,
    'resolutionProfile': profile.wireValue,
    'encodedSizeBytes': sizeBytes,
    'width': width,
    'height': height,
  };
}

img.Image _resizeToLongestSide(img.Image image, int longestSide) {
  if (image.width >= image.height) {
    return img.copyResize(
      image,
      width: longestSide,
      interpolation: img.Interpolation.linear,
    );
  }
  return img.copyResize(
    image,
    height: longestSide,
    interpolation: img.Interpolation.linear,
  );
}

Future<String> _writeTempPng(
  img.Image image,
  String imageId,
  String tempDirPath,
) async {
  final tempDir = Directory(tempDirPath)..createSync(recursive: true);
  final tempFile = File(
    '${tempDir.path}/${imageId}__target1080_temp.png',
  );
  await tempFile.writeAsBytes(img.encodePng(image));
  return tempFile.path;
}

Future<void> _encodeWebpLossy({
  required String cwebpPath,
  required String inputPngPath,
  required int quality,
  required String outputPath,
}) async {
  final result = await Process.run(cwebpPath, <String>[
    '-preset', 'photo',
    '-q', quality.toString(),
    inputPngPath,
    '-o', outputPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Falha no cwebp para $outputPath: ${result.stderr}');
  }
}

Future<String> _cwebpVersion(String cwebpPath) async {
  final result = await Process.run(cwebpPath, <String>['-version']);
  final firstLine = (result.stdout as String).trim().split('\n').first;
  return firstLine.trim();
}

String? _packageVersionFromLock(String packageName) {
  final lockFile = File('pubspec.lock');
  if (!lockFile.existsSync()) {
    return null;
  }
  final content = lockFile.readAsStringSync();
  final packageBlockPattern = RegExp(
    '^  $packageName:\\n(?:^ {4}.*\\n?)*',
    multiLine: true,
  );
  final block = packageBlockPattern.firstMatch(content)?.group(0);
  if (block == null) {
    return null;
  }
  final versionPattern = RegExp(r'version: "([^"]+)"');
  return versionPattern.firstMatch(block)?.group(1);
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Lê `selected_images.txt` (gerado por `select_images.dart`) e conta
/// quantas imagens foram selecionadas, para validar que `generated/source/`
/// não diverge do que a seleção determinística produziu. Retorna `null`
/// (sem checagem) se o arquivo não existir — caso de datasets sintéticos
/// usados em teste, ou de quem popula o diretório de origem manualmente
/// sem passar por select_images.dart.
int? _expectedCountFromSelection([
  String path = 'generated/selected_images.txt',
]) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final dataLines = file.readAsLinesSync().where(
        (line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'),
      );
  return dataLines.length;
}

class PrepareDatasetOptions {
  PrepareDatasetOptions({
    required this.sourceDirPath,
    required this.outputDirPath,
    required this.cwebpPath,
    required this.tempDirPath,
    required this.datasetId,
    this.expectedImageCount,
  });

  final String sourceDirPath;
  final String outputDirPath;
  final String cwebpPath;
  final String tempDirPath;
  final String datasetId;

  /// Contagem esperada de imagens-fonte para validação; `null` desativa a
  /// checagem. Via CLI (`parse`), é derivada automaticamente de
  /// `selected_images.txt` (ver [_expectedCountFromSelection]) — não há
  /// número fixo no código. Testes de integração com datasets sintéticos
  /// passam esse valor manualmente.
  final int? expectedImageCount;

  static PrepareDatasetOptions parse(List<String> arguments) {
    return PrepareDatasetOptions(
      sourceDirPath: 'generated/source',
      outputDirPath: 'generated',
      cwebpPath: 'bin/cwebp',
      tempDirPath: Directory.systemTemp.path,
      datasetId: defaultDatasetId,
      expectedImageCount: _expectedCountFromSelection(),
    );
  }
}
