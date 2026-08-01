# image-analysis-server

Servidor HTTP local estático usado no benchmark de formato/qualidade/resolução
de imagens. Serve os arquivos já preparados em `dataset/generated/`
(manifesto, referências e variantes) sem transformar, recomprimir ou fazer
cache de nada. Ver
[../docs/architecture-notes.md](../docs/architecture-notes.md) para a
justificativa dessas restrições dentro do desenho experimental.

## Requisitos

- Node.js 22.x (testado com 22.19.0)
- npm 10.x

## Instalação

```bash
cd image_analysis_server
npm ci
```

## Execução

```bash
npm run start -- --root ../dataset/generated --host 0.0.0.0 --port 8080
```

No celular Android, usar o IPv4 do computador na mesma rede Wi-Fi — nunca
`localhost`:

```text
http://192.168.1.50:8080/
```

## Rotas

```text
GET /health
GET /manifest.json
GET /references/<arquivo>.png
GET /variants/<arquivo>.jpg
GET /variants/<arquivo>.webp
```

Apenas `GET` e `HEAD` são permitidos; qualquer outro método recebe `405`.

## Cabeçalhos

Toda resposta de arquivo ou de `/health` inclui:

```text
Cache-Control: no-store, no-cache, must-revalidate, max-age=0
Pragma: no-cache
Expires: 0
```

O servidor nunca envia `ETag` ou `Last-Modified`, então `If-None-Match` e
`If-Modified-Since` são efetivamente ignorados: toda resposta bem-sucedida é
`200` com o corpo completo, nunca `304`.

## Segurança

Caminhos são resolvidos com `path.resolve` e validados para permanecer
dentro da raiz configurada (`--root`). Segmentos `..`, caminhos absolutos e
bytes nulos são rejeitados com `403`. Não há listagem de diretório.

## Testes

```bash
npm test
```
