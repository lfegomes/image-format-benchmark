import 'dart:typed_data';
import 'dart:ui' as ui;

class DecodeException implements Exception {
  DecodeException(this.message);
  final String message;

  @override
  String toString() => 'DecodeException: $message';
}

class DecodeResult {
  const DecodeResult({
    required this.image,
    required this.decodeTimeUs,
  });

  /// A imagem decodificada. Quem chama é responsável por `image.dispose()`
  /// após usá-la (cálculo de SSIM, memória estimada, etc.).
  final ui.Image image;
  final int decodeTimeUs;

  int get width => image.width;
  int get height => image.height;
}

/// Decodifica os bytes de uma variante já baixada até o primeiro frame
/// pronto para uso, cronometrando apenas a decodificação (nunca o download
/// nem a renderização).
Future<DecodeResult> decodeImage(Uint8List bytes) async {
  final stopwatch = Stopwatch()..start();
  ui.Codec codec;
  ui.FrameInfo frame;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    frame = await codec.getNextFrame();
  } on Exception catch (e) {
    stopwatch.stop();
    throw DecodeException('Falha ao decodificar imagem: $e');
  }
  stopwatch.stop();
  codec.dispose();

  return DecodeResult(
    image: frame.image,
    decodeTimeUs: stopwatch.elapsedMicroseconds,
  );
}

/// `decoded_memory_estimated_bytes = decoded_width × decoded_height × 4`
/// (matriz RGBA de 32 bits). Não representa o consumo total do processo.
int estimatedMemoryBytes(int width, int height) => width * height * 4;
