import 'package:flutter/material.dart';

class DecodeTimeBar {
  const DecodeTimeBar({
    required this.label,
    required this.meanDecodeTimeUs,
    required this.isWebp,
  });

  final String label;
  final double meanDecodeTimeUs;
  final bool isWebp;
}

/// Gráfico de barras simples do tempo médio de decodificação por condição.
class DecodeTimeBarChart extends StatelessWidget {
  const DecodeTimeBarChart({super.key, required this.bars});

  final List<DecodeTimeBar> bars;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return const Center(child: Text('Sem dados'));
    }
    final maxValue = bars.map((b) => b.meanDecodeTimeUs).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final bar in bars)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    bar.meanDecodeTimeUs.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 28,
                    height: maxValue == 0
                        ? 2
                        : 160 * (bar.meanDecodeTimeUs / maxValue),
                    color: bar.isWebp ? Colors.teal : Colors.deepOrange,
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 40,
                    child: Text(
                      bar.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
