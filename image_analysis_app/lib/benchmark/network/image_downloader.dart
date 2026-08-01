import 'dart:io';
import 'dart:typed_data';

import '../models/image_variant.dart';

class DownloadException implements Exception {
  DownloadException(this.message, {this.httpStatusCode});
  final String message;
  final int? httpStatusCode;

  @override
  String toString() => 'DownloadException: $message';
}

class DownloadResult {
  const DownloadResult({
    required this.bytes,
    required this.downloadTimeUs,
    required this.httpStatusCode,
  });

  final Uint8List bytes;
  final int downloadTimeUs;
  final int httpStatusCode;
}

/// Resolve [relativePath] contra [baseUri] com `Uri.resolve`, rejeitando
/// caminhos absolutos ou com travessia de diretório antes de resolver.
Uri resolveSafeUri(Uri baseUri, String relativePath) {
  if (relativePath.isEmpty) {
    throw ArgumentError('Caminho relativo vazio');
  }
  if (relativePath.startsWith('/')) {
    throw ArgumentError('Caminho relativo não pode ser absoluto: '
        '$relativePath');
  }
  final segments = relativePath.split('/');
  if (segments.contains('..')) {
    throw ArgumentError('Caminho relativo com travessia de diretório: '
        '$relativePath');
  }
  final parsed = Uri.tryParse(relativePath);
  if (parsed == null || parsed.isAbsolute) {
    throw ArgumentError('Caminho relativo inválido: $relativePath');
  }
  return baseUri.resolve(relativePath);
}

/// Tempo máximo que o `HttpClient` mantém uma conexão ociosa no pool antes
/// de descartá-la. Deve ficar **abaixo** do `keepAliveTimeout` configurado
/// no servidor (`image_analysis_server/src/server.ts`, 65s) para que o
/// cliente sempre feche/renegocie a conexão antes que o servidor a feche
/// por baixo dele — do contrário, a próxima requisição num socket já
/// fechado pelo servidor recebe um reset de conexão (ver README, seção
/// "Reset de conexão HTTP durante a rodada").
const Duration httpClientIdleTimeout = Duration(seconds: 30);

/// Baixa uma variante sem cache, com uma nova requisição HTTP por chamada e
/// um parâmetro `run` único por tarefa. Reaproveita um único `HttpClient`
/// (e, portanto, o pool de conexões TCP subjacente) durante toda a rodada:
/// nada aqui cria ou fecha um `HttpClient` por tarefa.
class ImageDownloader {
  ImageDownloader({HttpClient? httpClient})
    : _httpClient = httpClient ?? (HttpClient()..idleTimeout = httpClientIdleTimeout);

  final HttpClient _httpClient;

  Future<DownloadResult> download({
    required Uri baseUri,
    required ImageVariant variant,
    required String runId,
  }) async {
    final resolvedUri = resolveSafeUri(baseUri, variant.relativeUrl);
    final uriWithRun = resolvedUri.replace(
      queryParameters: <String, String>{
        ...resolvedUri.queryParameters,
        'run': runId,
      },
    );

    final stopwatch = Stopwatch()..start();
    late final HttpClientResponse response;
    try {
      final request = await _httpClient.getUrl(uriWithRun);
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, must-revalidate',
      );
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      response = await request.close();
    } on Exception catch (e) {
      stopwatch.stop();
      throw DownloadException('Falha na requisição HTTP: $e');
    }

    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response) {
        builder.add(chunk);
      }
    } on Exception catch (e) {
      stopwatch.stop();
      throw DownloadException(
        'Falha ao ler o corpo da resposta: $e',
        httpStatusCode: response.statusCode,
      );
    }
    stopwatch.stop();

    if (response.statusCode != HttpStatus.ok) {
      throw DownloadException(
        'Status HTTP inesperado: ${response.statusCode}',
        httpStatusCode: response.statusCode,
      );
    }

    final bytes = builder.takeBytes();

    final contentLengthHeader = response.headers.value(
      HttpHeaders.contentLengthHeader,
    );
    if (contentLengthHeader != null) {
      final expectedLength = int.tryParse(contentLengthHeader);
      if (expectedLength != null && expectedLength != bytes.length) {
        throw DownloadException(
          'Content-Length divergente: esperado $expectedLength, '
          'recebido ${bytes.length}',
          httpStatusCode: response.statusCode,
        );
      }
    }

    if (bytes.length != variant.manifestSizeBytes) {
      throw DownloadException(
        'Tamanho divergente do manifesto para ${variant.variantId}: '
        'esperado ${variant.manifestSizeBytes}, recebido ${bytes.length}',
        httpStatusCode: response.statusCode,
      );
    }

    return DownloadResult(
      bytes: bytes,
      downloadTimeUs: stopwatch.elapsedMicroseconds,
      httpStatusCode: response.statusCode,
    );
  }

  void close() => _httpClient.close(force: true);
}
