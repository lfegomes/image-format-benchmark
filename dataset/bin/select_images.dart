// Seleciona, de forma determinística, um subconjunto das imagens
// disponíveis em input/ (candidatas, fornecidas pelo usuário) para servir
// como dataset fonte do experimento (generated/source/), seguindo a regra:
//   1. listar os arquivos do conjunto;
//   2. ordenar pelo nome;
//   3. selecionar os N primeiros;
//   4. salvar a lista em generated/selected_images.txt;
//   5. copiar somente esses arquivos para generated/source/.
//
// Uso (a partir da raiz do pacote `dataset/`):
//   dart run bin/select_images.dart
//   dart run bin/select_images.dart --count 10
//
// --count define quantas imagens entram no experimento (padrão: 30, o
// total de imagens que já acompanha este repositório em input/). Quem
// clonar o repositório pode escolher outro valor livremente — o restante
// do pipeline (prepare_dataset.dart, servidor, app) se ajusta sozinho,
// sem constantes fixas em outro lugar para atualizar manualmente.
import 'dart:io';

void main(List<String> arguments) {
  final options = _Options.parse(arguments);

  final inputDir = Directory('input');
  if (!inputDir.existsSync()) {
    stderr.writeln('Diretório de imagens de entrada não encontrado: '
        '${inputDir.path}. Coloque as imagens candidatas (PNG) lá antes '
        'de rodar este script.');
    exitCode = 1;
    return;
  }

  final sourceFiles = inputDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));

  if (sourceFiles.length < options.count) {
    stderr.writeln('Esperava pelo menos ${options.count} imagens PNG em '
        '${inputDir.path}, mas encontrou ${sourceFiles.length}.');
    exitCode = 1;
    return;
  }

  final selected = sourceFiles.take(options.count).toList();

  final sourceOutDir = Directory('generated/source');
  sourceOutDir.createSync(recursive: true);

  final selectedImagesFile = File('generated/selected_images.txt');

  final buffer = StringBuffer()
    ..writeln('# Seleção determinística de imagens de entrada')
    ..writeln('#')
    ..writeln('# Regra: listar arquivos de '
        '${_basename(inputDir.path)}/, ordenar pelo nome, selecionar os '
        '${options.count} primeiros.')
    ..writeln('#')
    ..writeln('# imageId,originalFilename');

  for (var i = 0; i < selected.length; i++) {
    final sourceFile = selected[i];
    final imageId = _imageId(i + 1);
    final destination = File('${sourceOutDir.path}/$imageId.png');
    sourceFile.copySync(destination.path);
    buffer.writeln('$imageId,${_basename(sourceFile.path)}');
    stdout.writeln('Copiado ${_basename(sourceFile.path)} -> '
        '${destination.path}');
  }

  selectedImagesFile.writeAsStringSync(buffer.toString());
  stdout.writeln('');
  stdout.writeln('${selected.length} imagens selecionadas.');
  stdout.writeln('Lista salva em: ${selectedImagesFile.path}');
}

String _imageId(int index) => 'image_${index.toString().padLeft(3, '0')}';

String _basename(String path) => path.split(Platform.pathSeparator).last;

class _Options {
  _Options({required this.count});

  final int count;

  static _Options parse(List<String> arguments) {
    var count = 30;

    for (var i = 0; i < arguments.length; i++) {
      switch (arguments[i]) {
        case '--count':
          count = int.parse(arguments[++i]);
      }
    }

    return _Options(count: count);
  }
}
