import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../benchmark/config/experiment_config.dart';
import '../benchmark/data/csv_exporter.dart';
import '../benchmark/data/reference_store.dart';
import '../benchmark/data/result_store.dart';
import '../benchmark/models/device_environment.dart';
import '../benchmark/models/experiment_manifest.dart';
import '../benchmark/runner/benchmark_progress.dart';
import '../benchmark/runner/benchmark_runner.dart';
import 'results_screen.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({
    super.key,
    required this.baseUri,
    required this.manifest,
    required this.experimentId,
    required this.deviceEnvironment,
    required this.csvFile,
    this.seed = 20260724,
  });

  final Uri baseUri;
  final ExperimentManifest manifest;
  final String experimentId;
  final DeviceEnvironment deviceEnvironment;
  final File csvFile;
  final int seed;

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

enum _RunPhase { preparing, running, failed, done }

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  late final BenchmarkProgress _progress;
  late final ResultStore _resultStore;
  BenchmarkRunner? _runner;
  _RunPhase _phase = _RunPhase.preparing;
  String? _prepareError;

  @override
  void initState() {
    super.initState();
    _progress = BenchmarkProgress(
      totalTasks: widget.manifest.variantCount * repetitionsPerVariant,
    );
    _resultStore = ResultStore(CsvExporter(widget.csvFile));
    _prepareAndRun();
  }

  Future<void> _prepareAndRun() async {
    final referenceStore = ReferenceStore();
    try {
      await _resultStore.open();
      await referenceStore.loadAll(widget.baseUri, widget.manifest);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _RunPhase.failed;
        _prepareError = 'Falha ao preparar a rodada: $e';
      });
      return;
    }

    final runner = BenchmarkRunner(
      baseUri: widget.baseUri,
      manifest: widget.manifest,
      experimentId: widget.experimentId,
      seed: widget.seed,
      deviceEnvironment: widget.deviceEnvironment,
      resultStore: _resultStore,
      referenceStore: referenceStore,
    );

    if (!mounted) {
      runner.dispose();
      return;
    }

    setState(() {
      _runner = runner;
      _phase = _RunPhase.running;
    });

    await runner.run(_progress);

    if (!mounted) return;
    setState(() => _phase = _RunPhase.done);
  }

  @override
  void dispose() {
    _runner?.dispose();
    unawaited(_resultStore.close());
    super.dispose();
  }

  void _cancel() {
    _runner?.cancel();
  }

  void _viewResults() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultsScreen(
          results: _resultStore.results,
          csvFile: widget.csvFile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Executando o experimento')),
      body: switch (_phase) {
        _RunPhase.preparing => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Carregando referências de SSIM...'),
              ],
            ),
          ),
        ),
        _RunPhase.failed => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _prepareError ?? 'Falha desconhecida',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
        _RunPhase.running || _RunPhase.done => AnimatedBuilder(
          animation: _progress,
          builder: (context, _) => _ProgressView(
            progress: _progress,
            onCancel: _phase == _RunPhase.running ? _cancel : null,
            onViewResults: _phase == _RunPhase.done ? _viewResults : null,
          ),
        ),
      },
    );
  }
}


class _ProgressView extends StatelessWidget {
  const _ProgressView({
    required this.progress,
    required this.onCancel,
    required this.onViewResults,
  });

  final BenchmarkProgress progress;
  final VoidCallback? onCancel;
  final VoidCallback? onViewResults;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.totalTasks == 0
        ? 0.0
        : progress.completedTasks / progress.totalTasks;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 8),
          Text('${progress.completedTasks} / ${progress.totalTasks} tarefas'),
          const SizedBox(height: 20),
          Text('Variante atual: ${progress.currentVariantId ?? '-'}'),
          Text('Repetição: ${progress.currentRepetition ?? '-'}'),
          Text('Sequência: ${progress.currentSequenceIndex ?? '-'}'),
          const SizedBox(height: 20),
          Text('Sucessos: ${progress.successCount}'),
          Text('Falhas: ${progress.failureCount}'),
          const SizedBox(height: 20),
          Text(
            'Tempo decorrido: ${progress.elapsed.elapsed.inSeconds}s',
          ),
          const Spacer(),
          if (onCancel != null)
            Center(
              child: OutlinedButton(
                onPressed: onCancel,
                child: Text(
                  progress.isCancelling ? 'Cancelando...' : 'Cancelar',
                ),
              ),
            ),
          if (onViewResults != null)
            Center(
              child: FilledButton(
                onPressed: onViewResults,
                child: const Text('Ver resultados'),
              ),
            ),
        ],
      ),
    );
  }
}
