import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../benchmark/config/experiment_config.dart';
import '../benchmark/data/device_info_provider.dart';
import '../benchmark/data/manifest_loader.dart';
import '../benchmark/models/device_environment.dart';
import '../benchmark/models/experiment_manifest.dart';
import 'benchmark_screen.dart';

enum _CheckStatus { idle, loading, ok, failed }

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://192.168.1.50:8080/',
  );

  _CheckStatus _healthStatus = _CheckStatus.idle;
  String? _healthError;

  _CheckStatus _manifestStatus = _CheckStatus.idle;
  String? _manifestError;
  ExperimentManifest? _manifest;

  DeviceEnvironment? _deviceEnvironment;
  String? _csvPath;
  final String _experimentId = 'exp-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _loadDeviceEnvironment();
    _resolveCsvPath();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceEnvironment() async {
    final environment = await collectDeviceEnvironment();
    if (!mounted) return;
    setState(() => _deviceEnvironment = environment);
  }

  Future<void> _resolveCsvPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      setState(() {
        _csvPath = '${dir.path}/$_experimentId.csv';
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _csvPath = '$_experimentId.csv');
    }
  }

  Uri? get _baseUri {
    final raw = _baseUrlController.text.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.endsWith('/') ? raw : '$raw/';
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return uri;
  }

  Future<void> _checkHealth() async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      setState(() {
        _healthStatus = _CheckStatus.failed;
        _healthError = 'URL-base inválida';
      });
      return;
    }

    setState(() {
      _healthStatus = _CheckStatus.loading;
      _healthError = null;
    });

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(baseUri.resolve('health'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _healthStatus = _CheckStatus.ok);
      } else {
        setState(() {
          _healthStatus = _CheckStatus.failed;
          _healthError = 'Status HTTP ${response.statusCode}';
        });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _healthStatus = _CheckStatus.failed;
        _healthError = 'Servidor inacessível: $e';
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadManifest() async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      setState(() {
        _manifestStatus = _CheckStatus.failed;
        _manifestError = 'URL-base inválida';
      });
      return;
    }

    setState(() {
      _manifestStatus = _CheckStatus.loading;
      _manifestError = null;
      _manifest = null;
    });

    final loader = ManifestLoader();
    try {
      final manifest = await loader.fetchAndValidate(baseUri);
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _manifestStatus = _CheckStatus.ok;
      });
    } on ManifestFetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _manifestStatus = _CheckStatus.failed;
        _manifestError = e.message;
      });
    } on ManifestValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _manifestStatus = _CheckStatus.failed;
        _manifestError = e.message;
      });
    } finally {
      loader.close();
    }
  }

  void _startBenchmark() {
    final baseUri = _baseUri;
    final manifest = _manifest;
    final deviceEnvironment = _deviceEnvironment;
    final csvPath = _csvPath;
    if (baseUri == null || manifest == null || deviceEnvironment == null || csvPath == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BenchmarkScreen(
          baseUri: baseUri,
          manifest: manifest,
          experimentId: _experimentId,
          deviceEnvironment: deviceEnvironment,
          csvFile: File(csvPath),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final canStart =
        manifest != null && _deviceEnvironment != null && _csvPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark de imagens — configuração')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'URL-base do servidor',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.50:8080/',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _healthStatus == _CheckStatus.loading
                      ? null
                      : _checkHealth,
                  child: const Text('Testar conexão'),
                ),
                const SizedBox(width: 12),
                _StatusIndicator(status: _healthStatus, errorMessage: _healthError),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _manifestStatus == _CheckStatus.loading
                      ? null
                      : _loadManifest,
                  child: const Text('Carregar manifesto'),
                ),
                const SizedBox(width: 12),
                _StatusIndicator(
                  status: _manifestStatus,
                  errorMessage: _manifestError,
                ),
              ],
            ),
            if (manifest != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${manifest.sourceImageCount} imagens · '
                    '${manifest.variantCount} variantes · '
                    '${manifest.variantCount * repetitionsPerVariant} tarefas',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Dispositivo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(_deviceEnvironment?.deviceLabel ?? 'Carregando...'),
            const SizedBox(height: 20),
            const Text(
              'Arquivo CSV de resultados',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(_csvPath ?? 'Resolvendo caminho...'),
            const SizedBox(height: 28),
            Center(
              child: FilledButton(
                onPressed: canStart ? _startBenchmark : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('Executar experimento'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status, required this.errorMessage});

  final _CheckStatus status;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _CheckStatus.idle:
        return const SizedBox.shrink();
      case _CheckStatus.loading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _CheckStatus.ok:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _CheckStatus.failed:
        return Expanded(
          child: Text(
            errorMessage ?? 'Falha',
            style: const TextStyle(color: Colors.red),
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }
}
