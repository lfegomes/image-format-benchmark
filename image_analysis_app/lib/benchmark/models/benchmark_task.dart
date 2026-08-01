import 'image_variant.dart';

/// Uma repetição de medição de uma variante.
class BenchmarkTask {
  const BenchmarkTask({
    required this.variant,
    required this.repetition,
    required this.sequenceIndex,
  });

  final ImageVariant variant;
  final int repetition;
  final int sequenceIndex;

  BenchmarkTask copyWithSequenceIndex(int sequenceIndex) {
    return BenchmarkTask(
      variant: variant,
      repetition: repetition,
      sequenceIndex: sequenceIndex,
    );
  }
}
