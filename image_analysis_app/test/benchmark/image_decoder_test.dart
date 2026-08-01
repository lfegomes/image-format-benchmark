import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_analysis_app/benchmark/decoding/image_decoder.dart';

void main() {
  test('decodeImage decodifica um PNG válido e mede o tempo', () async {
    final source = img.Image(width: 16, height: 10);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    final pngBytes = Uint8List.fromList(img.encodePng(source));

    final result = await decodeImage(pngBytes);

    expect(result.width, 16);
    expect(result.height, 10);
    expect(result.decodeTimeUs, greaterThanOrEqualTo(0));

    result.image.dispose();
  });

  test('decodeImage lança DecodeException para bytes inválidos', () async {
    final garbage = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    await expectLater(decodeImage(garbage), throwsA(isA<DecodeException>()));
  });

  test('estimatedMemoryBytes calcula largura × altura × 4', () {
    expect(estimatedMemoryBytes(1080, 720), 1080 * 720 * 4);
    expect(estimatedMemoryBytes(0, 0), 0);
  });
}
