# dataset

Pacote Dart que prepara o dataset do benchmark: seleciona um
subconjunto determinístico de imagens de entrada e gera 12 variantes
JPEG/WebP por imagem (2 formatos × 3 qualidades × 2 resoluções) + o
`manifest.json` consumidos pelo app Flutter através do servidor Node.

## Requisitos

- Dart SDK ^3.12.2
- `cwebp` (do projeto libwebp), usado para gerar WebP com perdas — ver
  "Obtendo o cwebp" abaixo.

## Estrutura

```text
dataset/
  pubspec.yaml
  bin/
    select_images.dart        # seleção determinística das imagens de entrada
    prepare_dataset.dart      # geração das variantes + manifest.json
    cwebp                     # binário nativo (baixado à parte, não versionado)
  test/
    prepare_dataset_test.dart
  input/                      # você coloca aqui as imagens candidatas (PNG)
  generated/                  # gerado: tudo que o pipeline produz
    selected_images.txt       # regra + lista da seleção
    source/                   # as N imagens selecionadas
    manifest.json
    references/
    variants/
```

Detalhe: `input/` e `generated/` são ignorados pelo Git.

## Passo a passo

### 1. Colocar imagens de entrada em `input/`

Copie para `dataset/input/` os arquivos PNG candidatos. As imagens precisam ter alta resolução (lado maior acima de 1080px, já que o
perfil `target1080` precisa reduzir, e não ampliar).

### 2. Selecionar as imagens determinísticamente

```bash
cd dataset
dart pub get
dart run bin/select_images.dart
```

Isso ordena os arquivos de `input/` pelo nome, pega os N primeiros (padrão:
30), copia para
`generated/source/image_001.png`..`generated/source/image_0NN.png` e
grava `generated/selected_images.txt` com o mapeamento
nome-original → id.

Quer testar com menos imagens? Use `--count`:

```bash
dart run bin/select_images.dart --count 10
```

### 3. Obter o `cwebp`

O pacote `image` não codifica WebP com perdas — o preparador chama o
binário `cwebp` (libwebp) via `Process.run`. Baixe o release oficial para
o seu sistema/arquitetura em
https://developers.google.com/speed/webp/download e
coloque o executável em `dataset/bin/cwebp`.

### 4. Gerar as variantes

```bash
dart run bin/prepare_dataset.dart
```

Gera `generated/manifest.json`, `generated/references/*.png` (uma
referência normalizada de 1080px por imagem) e
`generated/variants/*.{jpg,webp}` (12 variantes por imagem, então o total
de variantes é `12 × quantidade de imagens selecionadas`). Falha
explicitamente se alguma codificação não for suportada, ou se a contagem
de imagens em `generated/source/` divergir de `selected_images.txt` —
nunca produz
um manifesto incompleto ou inconsistente silenciosamente.

### 5. Servir o resultado

`generated/` é exatamente o diretório que o `image_analysis_server` deve
apontar com `--root`:

```bash
cd ../image_analysis_server
npm run start -- --root ../dataset/generated --host 0.0.0.0 --port 8080
```

## Testes

```bash
cd dataset
dart test
```

O teste de integração gera duas imagens sintéticas em memória, roda o
preparador de ponta a ponta contra elas e confere que as 12 variantes por
imagem, as dimensões e os tamanhos batem com o manifesto. Ele exige que
`bin/cwebp` exista (passo 3 acima).

## Autonomia

Este pacote não importa nada de `image_analysis_app` ou
`image_analysis_server`, mas algumas constantes do experimento (qualidades,
lado maior alvo, repetições) estão duplicadas. Caso alterar algo em
`bin/prepare_dataset.dart` é necessário atualizar também em
`../image_analysis_app/lib/benchmark/config/experiment_config.dart`.

O **tamanho do dataset não é uma dessas constantes** e não precisa ser
sincronizado manualmente em lugar nenhum:

1. `select_images.dart --count N` decide quantas imagens entram e grava
   `generated/selected_images.txt`.
2. `prepare_dataset.dart` lê esse arquivo para saber quantas imagens
   esperar em `generated/source/` (função `_expectedCountFromSelection`) —
   sem `generated/selected_images.txt`, ele simplesmente confia no que
   encontrar lá.
3. `manifest.json` registra a contagem real de imagens/variantes geradas.
4. O app Flutter valida e usa a contagem vinda do `manifest.json` em
   tempo de execução (`ManifestLoader`, `BenchmarkProgress`) — não tem
   nenhuma constante de tamanho de dataset no código.

