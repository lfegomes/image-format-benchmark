import 'package:flutter/material.dart';

class SizeVsSsimPoint {
  const SizeVsSsimPoint({
    required this.bitsPerPixel,
    required this.ssim,
    required this.isWebp,
    required this.label,
  });

  final double bitsPerPixel;
  final double ssim;
  final bool isWebp;
  final String label;
}

/// Gráfico de dispersão simples (bits por pixel × SSIM), um ponto por
/// condição (formato × qualidade × resolução).
class SizeVsSsimChart extends StatelessWidget {
  const SizeVsSsimChart({super.key, required this.points});

  final List<SizeVsSsimPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Sem dados'));
    }
    return CustomPaint(
      painter: _ScatterPainter(points, Theme.of(context)),
      child: const SizedBox.expand(),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter(this.points, this.theme);

  final List<SizeVsSsimPoint> points;
  final ThemeData theme;

  static const double _padding = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;

    final plotWidth = size.width - _padding * 2;
    final plotHeight = size.height - _padding * 2;

    canvas.drawLine(
      Offset(_padding, size.height - _padding),
      Offset(size.width - _padding, size.height - _padding),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_padding, _padding),
      Offset(_padding, size.height - _padding),
      axisPaint,
    );

    final maxBpp = points.map((p) => p.bitsPerPixel).reduce((a, b) => a > b ? a : b);
    final minSsim = points.map((p) => p.ssim).reduce((a, b) => a < b ? a : b);
    final maxSsim = points.map((p) => p.ssim).reduce((a, b) => a > b ? a : b);
    final ssimRange = (maxSsim - minSsim).abs() < 1e-9 ? 1.0 : maxSsim - minSsim;

    for (final point in points) {
      final x = _padding + (point.bitsPerPixel / (maxBpp == 0 ? 1 : maxBpp)) * plotWidth;
      final y = size.height - _padding - ((point.ssim - minSsim) / ssimRange) * plotHeight;

      final paint = Paint()
        ..color = point.isWebp ? Colors.teal : Colors.deepOrange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 5, paint);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: 'bits/pixel →',
      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width - _padding - textPainter.width, size.height - _padding + 8),
    );

    textPainter.text = TextSpan(
      text: '↑ SSIM',
      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(4, 4));
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) =>
      oldDelegate.points != points;
}
