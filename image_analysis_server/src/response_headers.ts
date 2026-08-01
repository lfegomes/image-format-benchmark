import path from "node:path";

/**
 * Cabeçalhos que desabilitam qualquer cache em requisições condicionais,
 * proxies ou no próprio HTTP client do app — cada tarefa do benchmark deve
 * baixar os bytes de novo, nunca reaproveitar uma resposta em cache.
 */
export const NO_CACHE_HEADERS: Readonly<Record<string, string>> = {
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  Pragma: "no-cache",
  Expires: "0",
};

const CONTENT_TYPE_BY_EXTENSION: Readonly<Record<string, string>> = {
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
};

/**
 * Resolve o Content-Type pela extensão do arquivo. Lança se a extensão não
 * for uma das explicitamente suportadas pelo experimento: apenas JPEG e
 * WebP com perdas, além do manifesto em JSON e das referências em PNG.
 */
export function contentTypeFor(filePath: string): string {
  const extension = path.extname(filePath).toLowerCase();
  const contentType = CONTENT_TYPE_BY_EXTENSION[extension];
  if (!contentType) {
    throw new Error(`Extensão de arquivo não suportada: ${extension}`);
  }
  return contentType;
}

export function buildFileHeaders(
  filePath: string,
  contentLength: number,
): Record<string, string> {
  return {
    ...NO_CACHE_HEADERS,
    "Content-Type": contentTypeFor(filePath),
    "Content-Length": String(contentLength),
  };
}
