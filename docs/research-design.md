# Desenho da pesquisa

Este repositório é o software desenvolvido para um artigo científico
empírico sobre carregamento de imagens fotográficas em aplicações
Flutter. Este documento explica a motivação acadêmica, a pergunta de pesquisa, as hipóteses e o desenho experimental por trás do código.

## Motivação

Aplicações móveis frequentemente transferem imagens com dimensões ou
qualidade superiores às necessárias para exibição. O tamanho do arquivo
codificado afeta a transferência, enquanto a resolução decodificada afeta
a quantidade de pixels mantida em memória — e um arquivo menor não
necessariamente exige menos tempo de decodificação. No desenvolvimento
Flutter, formato, qualidade e resolução são frequentemente escolhidos por
convenção ou tentativa e erro; este trabalho produz evidências mensuráveis
sobre essas decisões em um pipeline controlado.

## Pergunta de pesquisa

> Como o formato de codificação, o nível de qualidade e a resolução
> previamente preparada influenciam o tamanho transferido, o tempo de
> download, o tempo de decodificação e a qualidade estrutural de imagens
> fotográficas carregadas por uma aplicação Flutter em ambiente Android
> controlado?

A memória estimada da imagem decodificada é registrada como métrica
derivada das dimensões, não como consumo total do processo Flutter.

## Hipóteses

- **H1:** limitar previamente o lado maior da imagem a 1080 pixels reduz o
  tamanho transferido e a memória estimada da matriz decodificada.
- **H2:** WebP pode produzir arquivos menores que JPEG quando comparados
  em níveis próximos de SSIM.
- **H3:** um arquivo codificado menor não necessariamente apresenta menor
  tempo de decodificação.
- **H4:** níveis intermediários de qualidade podem apresentar relações
  mais favoráveis entre quantidade de bytes e SSIM do que o nível mais
  alto para parte das imagens avaliadas.

As hipóteses são avaliadas pelos dados coletados com este software — o
código não assume nenhuma delas como verdadeira, apenas mede.

## Objetivos

**Geral:** desenvolver e avaliar empiricamente uma ferramenta em
Flutter/Dart para comparar estratégias de preparação e carregamento de
imagens fotográficas, considerando formato, qualidade, resolução, tamanho
transferido, desempenho de carregamento, memória estimada e qualidade
estrutural.

**Específicos:**

1. Construir um conjunto controlado de variantes JPEG e WebP de imagens
   fotográficas.
2. Comparar os níveis de qualidade 70, 85 e 95.
3. Comparar resolução original e resolução com lado maior limitado a 1080
   pixels.
4. Implementar um preparador de dataset em Dart.
5. Implementar um servidor HTTP local em Node.js/TypeScript.
6. Implementar um aplicativo Flutter para baixar e decodificar as
   variantes.
7. Medir separadamente download e decodificação.
8. Registrar bytes recebidos, dimensões, memória estimada e ambiente do
   dispositivo.
9. Calcular SSIM em relação a uma referência comum.
10. Exportar os resultados e aplicar estatística descritiva.
11. Identificar estratégias não dominadas por meio da relação entre bytes,
    tempo e SSIM, sem criar um recomendador automático.

## Delimitação do escopo

**Incluído:** 30 imagens fotográficas naturais de alta resolução; JPEG e
WebP; qualidades 70, 85 e 95; resolução original e `target1080`; servidor
HTTP local; carregamento novo em cada repetição, sem reaproveitamento de
cache; Android; tamanho codificado, download, decodificação, tempo total,
dimensões, memória estimada e SSIM; CSV incremental e estatística
descritiva.

**Fora do escopo:** PNG como formato de saída; imagens com texto, ícones,
diagramas ou transparência; comparação de algoritmos de interpolação;
cache como fator experimental; processamento de vídeo; inteligência
artificial; camada automática de recomendação; banco de dados; dashboard
sofisticado; iOS e Web (salvo como extensão futura); medição de CPU, GPU,
bateria ou energia.

## Desenho experimental

### Dataset de referência

O conjunto principal é formado por **30 imagens de referência em PNG**,
do conjunto de validação do CLIC 2024 — criado para estudos de compressão, 
com fotografias e lado maior padronizado em 2048 pixels. Motivos para essa escolha:

- são fotografias naturais, fornecidas em PNG;
- o lado maior de 2048px permite comparar `original` com `target1080` por
  redução real (nunca ampliação);
- o conjunto foi publicado especificamente para avaliação de compressão;
- o download completo é pequeno o suficiente para o projeto.
- **Licença:** ver termos do CLIC (https://clic.compression.cc) e das
  imagens de origem no Unsplash. Uso restrito a pesquisa acadêmica não
  comercial neste projeto.

**Alternativa considerada e descartado:** o Kodak Lossless True Color Image Suite, porque suas
imagens têm apenas 768×512 ou 512×768 pixels. Como o experimento compara
resolução original com `target1080` (1080px), usar Kodak exigiria
ampliação em vez de redução, invertendo o significado da variável
experimental.

### Variáveis independentes

- **Formato:** JPEG ou WebP.
- **Qualidade:** 70, 85 ou 95.
- **Resolução:** original ou `target1080` (lado maior reduzido a 1080px).

O método de redimensionamento é fixo e documentado (interpolação linear),
não é uma variável da pesquisa.

### Repetições e amostragem

Cada variante é executada três vezes por dispositivo, com uma nova
requisição HTTP a cada repetição e ordem de tarefas embaralhada. As três
repetições não são tratadas como três observações independentes: a
mediana das três repetições é usada como a observação de cada imagem em
cada condição, e cada **imagem** (não cada repetição) é a unidade
amostral na agregação estatística.

### Dispositivos

Mínimo de um Android físico; o ideal são dois aparelhos de classes de
desempenho diferentes. Com um único dispositivo, os resultados de
desempenho não devem ser generalizados entre classes de hardware — essa
limitação deve ser declarada explicitamente no artigo.

## Métricas

### Principais

- **Tamanho transferido** (`received_size_bytes`, bytes): quantos bytes
  do arquivo codificado a aplicação efetivamente recebeu pela rede.
- **Tempo de decodificação** (`decode_time_us`, microssegundos): do
  início da decodificação até o primeiro frame pronto (`ui.Image`), sem
  incluir renderização na tela.
- **SSIM** (adimensional, 0–1): similaridade estrutural entre a variante
  decodificada e uma referência comum normalizada (ver metodologia
  abaixo).

### Secundárias

- **Tempo de download** (`download_time_us`, microssegundos): do início
  da requisição HTTP até o último byte do corpo recebido.
- **Tempo total** (`total_load_time_us`, microssegundos): download +
  decodificação somados.

Secundárias porque dependem também da rede local, mesmo em ambiente
controlado.

### Derivada

- **Memória estimada** (`decoded_memory_estimated_bytes`, bytes):
  `decoded_width × decoded_height × 4` (matriz RGBA de 32 bits) — uma
  estimativa a partir das dimensões decodificadas, não o consumo total
  real do processo Flutter.

### Métrica de validação

- **Dimensões decodificadas** (`decoded_width`, `decoded_height`,
  pixels): largura e altura reais da imagem após a decodificação,
  conferidas contra o `width`/`height` do manifesto. Não é uma métrica de
  pesquisa em si — garante que nenhuma tarefa foi silenciosamente
  redimensionada, e alimenta o cálculo da memória estimada.

### Metodologia do SSIM

Calculado contra uma referência comum de 1080px, fora dos cronômetros de
download e decodificação, uma vez por variante e dispositivo (reaproveitado
nas repetições, já que o pipeline de decodificação é determinístico). Não é
definido um limiar universal de "qualidade aceitável" — isso exigiria um
estudo subjetivo com pessoas, fora do escopo deste trabalho.


## Plano de análise estatística

Para cada imagem e condição: mediana das três repetições, imagem como
unidade amostral, agregação por formato, qualidade, resolução e
dispositivo. Calculados: média, mediana, desvio-padrão, mínimo e máximo,
redução percentual de bytes e de memória estimada, diferença percentual
nos tempos, e distribuição do SSIM.

Análises principais: JPEG vs. WebP na mesma resolução; JPEG vs. WebP em
níveis próximos de SSIM (os números 70/85/95 não são equivalentes entre
codecs); original vs. `target1080`; bytes (ou bits por pixel) vs. SSIM;
tamanho vs. tempo de download; tamanho vs. tempo de decodificação;
resolução vs. memória estimada; comparação por dispositivo; identificação
de estratégias na fronteira de Pareto.

## Contribuição esperada

Uma ferramenta reproduzível (preparador de dataset, servidor de arquivos
estáticos e aplicativo de benchmark) e um estudo empírico sobre como
formato, qualidade e resolução influenciam diferentes recursos no
carregamento de imagens em Flutter. Um exemplo de conclusão compatível
com o desenho da pesquisa, sem antecipar valores:

> Entre as condições avaliadas, determinadas variantes permaneceram na
> fronteira de Pareto por reduzirem a quantidade de bytes sem serem
> dominadas por outra configuração em SSIM e tempo de decodificação.

## Limitações previstas

- Resultados aplicáveis principalmente a fotografias naturais semelhantes
  às do CLIC 2024 — não a imagens com texto, ícones, diagramas ou
  transparência.
- A rede local, mesmo controlada, ainda introduz variação nos tempos de
  download.
- A memória estimada não equivale ao consumo total do processo Flutter.
- Os parâmetros numéricos de qualidade (70/85/95) não são equivalentes
  entre JPEG e WebP — as comparações sempre consideram também o SSIM
  resultante.
- SSIM não substitui avaliação subjetiva de qualidade percebida por
  pessoas.
- Resultados obtidos em Android não devem ser generalizados
  automaticamente para iOS ou Web.
- Resultados dependem das versões específicas do Flutter, Android e dos
  codecs usados na coleta.
- Um único dispositivo físico reduz a validade externa das conclusões de
  desempenho.


