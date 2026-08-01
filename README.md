# Benchmark de formato/qualidade/resolução de imagens

Ferramenta de pesquisa empírica em três partes:
- Pacote Dart que prepara o dataset do benchmark
- Servidor HTTP local em Node.js/TypeScript
- Aplicativo Flutter de benchmark — para medir como formato, qualidade e resolução de imagens fotográficas afetam o carregamento em aplicações Flutter. 

A referência técnica completa de tudo o que o software faz e como cada cálculo ocorre está em [docs/how-it-works.md](docs/how-it-works.md); as decisões de arquitetura por trás dessa implementação estão em [docs/architecture-notes.md](docs/architecture-notes.md). Este README documenta como rodar e operar o software, e como interpretar resultados.

## Estrutura

Três subprojetos independentes — cada um com seu próprio README com instruções detalhadas de uso:

```text
image_analysis/
  dataset/                # Prepara o dataset do benchmark
  image_analysis_app/     # App Flutter de benchmark
  image_analysis_server/  # Servidor HTTP local
```

## O que este projeto mede

O objetivo é comparar, para as mesmas fotografias, como
**formato** (JPEG × WebP), **qualidade** (70 × 85 × 95) e **resolução**
(original × reduzida para 1080px) afetam o carregamento de uma imagem em
um app Flutter. Para cada variante preparada (12 por imagem: 2 formatos ×
3 qualidades × 2 resoluções), o app mede:

| Métrica | O que é | Tipo |
| --- | --- | --- |
| **Tamanho transferido** (`received_size_bytes`) | Quantos bytes o arquivo realmente ocupa na rede | Principal |
| **Tempo de decodificação** (`decode_time_us`) | Quanto tempo o Flutter leva para transformar os bytes baixados em uma imagem pronta para exibir na tela | Principal |
| **SSIM** | O quanto a imagem comprimida se parece estruturalmente com a imagem original (referência), de 0 a 1 — quanto mais perto de 1, mais parecida | Principal |
| **Tempo de download** (`download_time_us`) | Quanto tempo leva para baixar o arquivo via HTTP, do pedido até o último byte | Secundária |
| **Tempo total** (`total_load_time_us`) | Download + decodificação somados | Secundária |
| **Dimensões decodificadas** | Largura × altura reais da imagem depois de decodificada, conferidas contra o manifesto | Validação |
| **Memória estimada** (`decoded_memory_estimated_bytes`) | Quanto de RAM a matriz de pixels decodificada ocuparia (`largura × altura × 4`, assumindo RGBA de 32 bits) — **não** é o consumo total do app, só uma estimativa derivada das dimensões | Derivada |

Download e tempo total são secundárias porque dependem também da rede
local, mesmo em ambiente controlado. Cada variante é medida 3 vezes
(repetições); a tela de resultados usa a **mediana das 3 repetições de
cada imagem** como observação.

## Como rodar do zero

```bash
# 1. Preparar o dataset
# 1.1 As imagens de entrada já devem estar em dataset/input/;
# 1.2 Ver dataset/README.md para obter o cwebp
cd dataset
dart pub get
dart run bin/select_images.dart --count 30
dart run bin/prepare_dataset.dart

# 2. Subir o servidor local
cd ../image_analysis_server
npm ci
npm run start -- --root ../dataset/generated --host 0.0.0.0 --port 8080

# 3. Rodar o app apontando para o IPv4 do computador na mesma rede  (em outro terminal)
cd ../image_analysis_app
flutter run
```

Testes automatizados:

```bash
cd dataset && dart test
cd ../image_analysis_app && flutter test && flutter analyze
cd ../image_analysis_server && npm test
```

## Como operar o app

O app tem três telas, usadas sempre nesta ordem:

### 1. Configuração (tela inicial)

1. Digite a URL-base do servidor no campo de texto (ex.:
   `http://192.168.1.50:8080/` — o IPv4 do computador que está rodando o
   servidor.
2. **"Testar conexão"** (opcional, mas recomendado primeiro): faz uma
   requisição a `<url>/health`. Um 'check' verde confirma que o celular consegue
   alcançar o servidor na rede; um erro em vermelho mostra o motivo
   (servidor inacessível, status inesperado, URL inválida etc.) antes de
   perder tempo tentando carregar o manifesto.
3. **"Carregar manifesto"**: baixa `<url>/manifest.json` e valida sua
   estrutura (contagens batendo, IDs únicos, formatos/qualidades
   permitidos, 12 variantes por imagem, caminhos seguros). Se válido,
   aparece um resumo com as contagens reais dessa rodada (ex., para um
   dataset de 20 imagens: "20 imagens · 240 variantes · 720 tarefas" — os
   números variam conforme o tamanho do dataset preparado). Se inválido,
   aparece o motivo da rejeição.
4. A tela também mostra, automaticamente, o dispositivo detectado (modelo
   e versão do sistema) e o caminho onde o CSV desta rodada será salvo.
5. **"Executar experimento"** só fica habilitado depois que o manifesto
   carrega com sucesso. Ao tocar, o app segue para a tela de execução.

### 2. Execução

Assim que a tela abre, o app carrega as referências de SSIM (uma por
imagem do dataset, fora dos cronômetros) e começa a executar as tarefas —
variantes × repetições, sequencialmente, uma de cada vez, em uma ordem
embaralhada com semente fixa (nunca em paralelo).
A tela mostra, em tempo real: barra de progresso, variante e repetição
atuais, índice de sequência, contagem de sucessos/falhas e tempo
decorrido. Cada resultado é salvo no CSV imediatamente após a tarefa
terminar, não só no final.

- **"Cancelar"**: interrompe a rodada depois que a tarefa em andamento
  termina. Nada do que já foi salvo é perdido.
- Ao concluir (ou cancelar), aparece o botão **"Ver resultados"**.

### 3. Resultados

- Tabela agregada por condição (formato × qualidade × resolução): número
  de imagens, bytes médio, SSIM médio, tempo médio de decodificação, e uma
  ⭐ nas condições que estão na fronteira de Pareto (nenhuma outra condição
  é igual ou melhor nas duas métricas bytes/SSIM ao mesmo tempo).
- Dois gráficos: bits por pixel × SSIM (dispersão) e tempo médio de
  decodificação por condição (barras).
- Ícone de compartilhar (canto superior direito) exporta/compartilha o
  arquivo CSV da rodada.


## Entendendo a tela de resultados

Depois de rodar o experimento (ou cancelá-lo), a tela de resultados mostra
um resumo do que já está no CSV. Antes de agregar qualquer coisa, o app
calcula a **mediana das 3 repetições de cada imagem** em cada condição
(formato × qualidade × resolução): repetições não são tratadas como
observações independentes, cada imagem entra uma única vez por condição.

- **Aviso de exclusão** (só aparece se houver): quantas observações de
  imagem foram descartadas da agregação por não terem as 3 repetições
  válidas naquela condição. O CSV bruto continua com todas as repetições,
  inclusive as das imagens excluídas aqui.
- **Tabela agregada por condição** — cada linha é uma combinação
  formato × qualidade × resolução (ex.: `webp q85 target1080`):
  - **n**: quantas imagens entraram na média dessa condição.
  - **Bytes (média)**: tamanho médio transferido.
  - **SSIM (média)**: similaridade estrutural média com a imagem
    original (0–1; quanto mais perto de 1, mais parecida).
  - **Decode (média, µs)**: tempo médio de decodificação.
  - **Pareto**: marca as condições na fronteira de Pareto entre bytes
    e SSIM — nenhuma outra condição é igual-ou-melhor nas duas métricas
    ao mesmo tempo (menos bytes **e** SSIM maior ou igual, com pelo
    menos uma estritamente melhor). São os melhores compromissos
    tamanho/qualidade da rodada.
- **Gráfico de dispersão "Bytes por pixel × SSIM"**: eixo X = bits por
  pixel (`bytes médios × 8 / pixels`, uma forma de normalizar o tamanho
  independente da resolução da imagem), eixo Y = SSIM médio. Um ponto por
  condição, cor por formato (JPEG × WebP) — mostra visualmente o
  trade-off tamanho/qualidade.
- **Gráfico de barras "Tempo de decodificação por condição"**: tempo
  médio de decodificação (µs) por condição, cor por formato — mostra o
  custo de CPU de decodificar cada combinação (efeito de JPEG vs. WebP e
  de resolução original vs. reduzida).
- **Ícone de compartilhar** (canto superior direito): exporta/compartilha
  o arquivo CSV bruto da rodada.

## Detalhes

O binário do `cwebp` (usado pelo preparador para gerar WebP com perdas)
**não é versionado** no repositório — é específico de cada
sistema/arquitetura. Antes de rodar `dataset/bin/prepare_dataset.dart` em
uma máquina nova, baixe o `cwebp` correspondente ao seu SO/arquitetura em
https://developers.google.com/speed/webp/download e coloque o executável
em `dataset/bin/cwebp`. O preparador falha
explicitamente, com uma mensagem clara, se não encontrar o binário nesse
caminho. Ver `dataset/README.md` para o passo a passo completo (incluindo
como popular `dataset/input/` com imagens candidatas).
