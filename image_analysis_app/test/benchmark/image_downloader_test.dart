import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_analysis_app/benchmark/config/experiment_config.dart';
import 'package:image_analysis_app/benchmark/models/image_variant.dart';
import 'package:image_analysis_app/benchmark/network/image_downloader.dart';

void main() {
  group('resolveSafeUri', () {
    final baseUri = Uri.parse('http://192.168.1.50:8080/');

    test('resolve um caminho relativo simples', () {
      final resolved = resolveSafeUri(baseUri, 'manifest.json');
      expect(resolved.toString(), 'http://192.168.1.50:8080/manifest.json');
    });

    test('resolve um caminho aninhado', () {
      final resolved = resolveSafeUri(
        baseUri,
        'variants/image_001__original__jpeg__q70.jpg',
      );
      expect(
        resolved.toString(),
        'http://192.168.1.50:8080/variants/image_001__original__jpeg__q70.jpg',
      );
    });

    test('rejeita caminho absoluto', () {
      expect(
        () => resolveSafeUri(baseUri, '/variants/x.jpg'),
        throwsArgumentError,
      );
    });

    test('rejeita travessia de diretório', () {
      expect(
        () => resolveSafeUri(baseUri, 'variants/../../etc/passwd'),
        throwsArgumentError,
      );
    });

    test('rejeita caminho vazio', () {
      expect(() => resolveSafeUri(baseUri, ''), throwsArgumentError);
    });

    test('respeita subcaminhos na URL-base', () {
      final nestedBase = Uri.parse('http://192.168.1.50:8080/experimento/');
      final resolved = resolveSafeUri(nestedBase, 'manifest.json');
      expect(
        resolved.toString(),
        'http://192.168.1.50:8080/experimento/manifest.json',
      );
    });
  });

  group('ImageDownloader', () {
    late HttpServer server;
    late Uri baseUri;
    final payload = utf8.encode('conteudo-de-teste-da-variante');

    setUp(() async {
      server = await HttpServer.bind('127.0.0.1', 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
      server.listen((request) async {
        if (request.uri.path == '/variants/ok.jpg') {
          request.response.headers.set(
            HttpHeaders.contentLengthHeader,
            payload.length,
          );
          request.response.statusCode = 200;
          request.response.add(payload);
          await request.response.close();
        } else if (request.uri.path == '/variants/not-found.jpg') {
          request.response.statusCode = 404;
          await request.response.close();
        } else {
          request.response.statusCode = 500;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    ImageVariant variantFor(String relativeUrl, int expectedSize) {
      return ImageVariant(
        variantId: 'image_001__original__jpeg__q70',
        sourceImageId: 'image_001',
        relativeUrl: relativeUrl,
        referenceUrl: 'references/image_001__reference1080.png',
        format: ImageFormat.jpeg,
        quality: 70,
        resolutionProfile: ResolutionProfile.original,
        manifestSizeBytes: expectedSize,
        expectedWidth: 100,
        expectedHeight: 100,
      );
    }

    test('baixa os bytes corretos e mede o tempo de download', () async {
      final downloader = ImageDownloader();
      final result = await downloader.download(
        baseUri: baseUri,
        variant: variantFor('variants/ok.jpg', payload.length),
        runId: 'run-1',
      );

      expect(result.bytes, payload);
      expect(result.httpStatusCode, 200);
      expect(result.downloadTimeUs, greaterThanOrEqualTo(0));
      downloader.close();
    });

    test('lança DownloadException em status HTTP diferente de 200', () async {
      final downloader = ImageDownloader();
      await expectLater(
        downloader.download(
          baseUri: baseUri,
          variant: variantFor('variants/not-found.jpg', payload.length),
          runId: 'run-1',
        ),
        throwsA(isA<DownloadException>()),
      );
      downloader.close();
    });

    test('lança DownloadException quando o tamanho diverge do manifesto', () async {
      final downloader = ImageDownloader();
      await expectLater(
        downloader.download(
          baseUri: baseUri,
          variant: variantFor('variants/ok.jpg', payload.length + 1),
          runId: 'run-1',
        ),
        throwsA(isA<DownloadException>()),
      );
      downloader.close();
    });
  });
}
