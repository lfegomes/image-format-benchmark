import 'dart:typed_data';

import 'package:image/image.dart' as img;

class SsimException implements Exception {
  SsimException(this.message);
  final String message;

  @override
  String toString() => 'SsimException: $message';
}

/// Tamanho da janela deslizante (não sobreposta) usada no cálculo do SSIM.
const int ssimWindowSize = 8;

/// Constantes de estabilização de Wang et al. (2004), para luminância no
/// intervalo [0, 255]: C1 = (0.01·L)², C2 = (0.03·L)².
const double _ssimC1 = 0.01 * 0.01 * 255 * 255;
const double _ssimC2 = 0.03 * 0.03 * 255 * 255;

/// Calcula o SSIM entre os bytes codificados de uma variante e de sua
/// referência, decodificando ambos com `package:image` (independente da
/// decodificação cronometrada em `decoding/image_decoder.dart`, já que o
/// SSIM é sempre calculado fora dos cronômetros).
///
/// Implementação: luminância Rec. 601 (0.299 R + 0.587 G + 0.114 B), janela
/// 8×8 não sobreposta, sem ponderação gaussiana. Se as dimensões diferirem,
/// a imagem é redimensionada (interpolação linear) para o tamanho da
/// referência antes da comparação — ajuste feito somente para viabilizar a
/// comparação, nunca incluído nos cronômetros de qualidade.
double computeSsimFromBytes({
  required List<int> imageBytes,
  required List<int> referenceBytes,
}) {
  img.Image? image;
  img.Image? reference;
  try {
    image = img.decodeImage(Uint8List.fromList(imageBytes));
    reference = img.decodeImage(Uint8List.fromList(referenceBytes));
  } catch (e) {
    // package:image pode lançar erros de baixo nível (não apenas retornar
    // null) ao tentar identificar o formato de bytes malformados.
    throw SsimException('Falha ao decodificar imagem para cálculo de SSIM: $e');
  }
  if (image == null || reference == null) {
    throw SsimException('Falha ao decodificar imagem para cálculo de SSIM');
  }
  return computeSsim(image: image, reference: reference);
}

double computeSsim({required img.Image image, required img.Image reference}) {
  if (reference.width < ssimWindowSize || reference.height < ssimWindowSize) {
    throw SsimException(
      'Referência menor que a janela de SSIM '
      '(${ssimWindowSize}x$ssimWindowSize): '
      '${reference.width}x${reference.height}',
    );
  }

  final normalizedImage =
      (image.width == reference.width && image.height == reference.height)
      ? image
      : img.copyResize(
          image,
          width: reference.width,
          height: reference.height,
          interpolation: img.Interpolation.linear,
        );

  final imageLuminance = _luminanceMatrix(normalizedImage);
  final referenceLuminance = _luminanceMatrix(reference);

  final width = reference.width;
  final height = reference.height;

  var sum = 0.0;
  var windowCount = 0;

  for (var y = 0; y + ssimWindowSize <= height; y += ssimWindowSize) {
    for (var x = 0; x + ssimWindowSize <= width; x += ssimWindowSize) {
      sum += _windowSsim(
        imageLuminance,
        referenceLuminance,
        width,
        x,
        y,
      );
      windowCount++;
    }
  }

  if (windowCount == 0) {
    throw SsimException('Nenhuma janela completa de SSIM encontrada');
  }

  final result = sum / windowCount;

  // O resultado deve permanecer no intervalo esperado do SSIM.
  // Matematicamente, médias de SSIM por janela ficam bem dentro de
  // [-1, 1]; usamos uma margem de segurança só para pegar bugs (NaN,
  // divisão degenerada) sem rejeitar casos-limite legítimos.
  if (result.isNaN || result.isInfinite || result < -1.5 || result > 1.5) {
    throw SsimException(
      'SSIM fora do intervalo esperado ([-1.5, 1.5]): $result. '
      'Isso indica um bug no cálculo, não uma imagem realmente diferente.',
    );
  }

  return result;
}

Float64List _luminanceMatrix(img.Image image) {
  final matrix = Float64List(image.width * image.height);
  var index = 0;
  for (final pixel in image) {
    matrix[index] = pixel.luminance.toDouble();
    index++;
  }
  return matrix;
}

double _windowSsim(
  Float64List a,
  Float64List b,
  int width,
  int startX,
  int startY,
) {
  var sumA = 0.0;
  var sumB = 0.0;
  final sampleCount = ssimWindowSize * ssimWindowSize;

  for (var dy = 0; dy < ssimWindowSize; dy++) {
    final rowOffset = (startY + dy) * width + startX;
    for (var dx = 0; dx < ssimWindowSize; dx++) {
      sumA += a[rowOffset + dx];
      sumB += b[rowOffset + dx];
    }
  }

  final meanA = sumA / sampleCount;
  final meanB = sumB / sampleCount;

  var varianceA = 0.0;
  var varianceB = 0.0;
  var covariance = 0.0;

  for (var dy = 0; dy < ssimWindowSize; dy++) {
    final rowOffset = (startY + dy) * width + startX;
    for (var dx = 0; dx < ssimWindowSize; dx++) {
      final diffA = a[rowOffset + dx] - meanA;
      final diffB = b[rowOffset + dx] - meanB;
      varianceA += diffA * diffA;
      varianceB += diffB * diffB;
      covariance += diffA * diffB;
    }
  }
  varianceA /= sampleCount;
  varianceB /= sampleCount;
  covariance /= sampleCount;

  final numerator =
      (2 * meanA * meanB + _ssimC1) * (2 * covariance + _ssimC2);
  final denominator =
      (meanA * meanA + meanB * meanB + _ssimC1) *
      (varianceA + varianceB + _ssimC2);

  return numerator / denominator;
}
