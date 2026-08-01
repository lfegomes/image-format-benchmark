import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_analysis_app/benchmark/quality/ssim.dart';

img.Image _gradientImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = ((x * 13 + y * 7) % 256);
      image.setPixelRgb(x, y, value, (value + 64) % 256, (value + 128) % 256);
    }
  }
  return image;
}

Uint8List _encodePng(img.Image image) => Uint8List.fromList(img.encodePng(image));

void main() {
  test('SSIM de uma imagem contra si mesma é ~1', () {
    final image = _gradientImage(64, 64);
    final ssim = computeSsim(image: image, reference: image);
    expect(ssim, closeTo(1.0, 1e-9));
  });

  test('SSIM de imagens claramente diferentes é menor que 1', () {
    final reference = _gradientImage(64, 64);
    final different = img.Image(width: 64, height: 64);
    img.fill(different, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(
      different,
      x1: 0,
      y1: 32,
      x2: 63,
      y2: 63,
      color: img.ColorRgb8(255, 255, 255),
    );

    final ssim = computeSsim(image: different, reference: reference);

    expect(ssim, lessThan(0.9));
  });

  test('SSIM permanece em um intervalo plausível', () {
    final reference = _gradientImage(32, 32);
    final noisy = _gradientImage(32, 32);
    // Perturba levemente a imagem "ruidosa".
    for (var y = 0; y < noisy.height; y += 3) {
      for (var x = 0; x < noisy.width; x += 3) {
        noisy.setPixelRgb(x, y, 255, 0, 0);
      }
    }

    final ssim = computeSsim(image: noisy, reference: reference);

    expect(ssim, greaterThan(-1.0));
    expect(ssim, lessThanOrEqualTo(1.0));
  });

  test('redimensiona a variante quando as dimensões diferem da referência', () {
    final reference = _gradientImage(64, 64);
    final smallerVariant = img.copyResize(
      reference,
      width: 32,
      height: 32,
      interpolation: img.Interpolation.linear,
    );

    final ssim = computeSsim(image: smallerVariant, reference: reference);

    expect(ssim, greaterThan(0.5));
    expect(ssim, lessThanOrEqualTo(1.0));
  });

  test('computeSsimFromBytes decodifica PNG antes de comparar', () {
    final image = _gradientImage(32, 32);
    final bytes = _encodePng(image);

    final ssim = computeSsimFromBytes(imageBytes: bytes, referenceBytes: bytes);

    expect(ssim, closeTo(1.0, 1e-9));
  });

  test('lança SsimException quando a referência é menor que a janela', () {
    final tinyReference = img.Image(width: 4, height: 4);
    final image = img.Image(width: 4, height: 4);
    expect(
      () => computeSsim(image: image, reference: tinyReference),
      throwsA(isA<SsimException>()),
    );
  });

  test('lança SsimException para bytes que não decodificam', () {
    expect(
      () => computeSsimFromBytes(
        imageBytes: <int>[1, 2, 3],
        referenceBytes: <int>[1, 2, 3],
      ),
      throwsA(isA<SsimException>()),
    );
  });
}
