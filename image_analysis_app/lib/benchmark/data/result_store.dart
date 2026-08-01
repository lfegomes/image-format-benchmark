import '../models/benchmark_result.dart';
import 'csv_exporter.dart';

/// Combina persistência incremental em CSV com uma lista em memória usada
/// pela tela de resultados (tabela, filtros, agregações).
class ResultStore {
  ResultStore(this._csvExporter);

  final CsvExporter _csvExporter;
  final List<BenchmarkResult> _results = <BenchmarkResult>[];

  List<BenchmarkResult> get results => List.unmodifiable(_results);

  Future<void> open() => _csvExporter.open();

  Future<void> record(BenchmarkResult result) async {
    await _csvExporter.appendResult(result);
    _results.add(result);
  }

  Future<void> close() => _csvExporter.close();
}
