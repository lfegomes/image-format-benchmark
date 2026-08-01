import 'package:flutter/foundation.dart';

enum BenchmarkPhase { idle, running, cancelling, completed }

/// Estado observável de uma rodada, para a tela de execução. Usa
/// `ChangeNotifier`, um dos mecanismos nativos de gerenciamento de estado
/// do Flutter — dispensa pacotes extras para uma tela deste tamanho.
class BenchmarkProgress extends ChangeNotifier {
  BenchmarkProgress({required this.totalTasks});

  final int totalTasks;

  BenchmarkPhase phase = BenchmarkPhase.idle;
  int completedTasks = 0;
  int successCount = 0;
  int failureCount = 0;
  String? currentVariantId;
  int? currentRepetition;
  int? currentSequenceIndex;
  final Stopwatch elapsed = Stopwatch();

  bool get isCancelling => phase == BenchmarkPhase.cancelling;

  void start() {
    phase = BenchmarkPhase.running;
    completedTasks = 0;
    successCount = 0;
    failureCount = 0;
    elapsed
      ..reset()
      ..start();
    notifyListeners();
  }

  void updateCurrentTask({
    required String variantId,
    required int repetition,
    required int sequenceIndex,
  }) {
    currentVariantId = variantId;
    currentRepetition = repetition;
    currentSequenceIndex = sequenceIndex;
    notifyListeners();
  }

  void recordSuccess() {
    completedTasks++;
    successCount++;
    notifyListeners();
  }

  void recordFailure() {
    completedTasks++;
    failureCount++;
    notifyListeners();
  }

  void requestCancel() {
    if (phase == BenchmarkPhase.running) {
      phase = BenchmarkPhase.cancelling;
      notifyListeners();
    }
  }

  void complete() {
    phase = BenchmarkPhase.completed;
    elapsed.stop();
    notifyListeners();
  }
}
