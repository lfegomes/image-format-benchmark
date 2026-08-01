import { promises as fs } from "node:fs";
import path from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";

import { buildFileHeaders } from "./response_headers.js";

export interface ServeResult {
  status: number;
  bytesSent: number;
}

/**
 * Resolve um caminho de URL para um caminho absoluto de arquivo dentro de
 * `rootDir`, ou retorna `null` se o caminho for inseguro (`..`, absoluto,
 * bytes nulos).
 */
export function resolveSafePath(
  rootDir: string,
  urlPath: string,
): string | null {
  if (urlPath.includes("\0")) {
    return null;
  }

  let decoded: string;
  try {
    decoded = decodeURIComponent(urlPath);
  } catch {
    return null;
  }
  if (decoded.includes("\0")) {
    return null;
  }

  const segments = decoded.split("/").filter((segment) => segment.length > 0);
  if (segments.includes("..") || segments.includes(".")) {
    return null;
  }

  const resolvedRoot = path.resolve(rootDir);
  const candidate = path.resolve(resolvedRoot, ...segments);
  const relative = path.relative(resolvedRoot, candidate);

  if (relative === "") {
    // O próprio diretório raiz nunca é um arquivo servível.
    return null;
  }
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    return null;
  }

  return candidate;
}

/**
 * Serve um único arquivo estático dentro de `rootDir`. Sempre responde com
 * o corpo completo (200), nunca 304: `If-None-Match` e `If-Modified-Since`
 * são ignorados porque o servidor nunca envia `ETag` ou `Last-Modified`.
 */
export async function serveStaticFile(
  req: IncomingMessage,
  res: ServerResponse,
  rootDir: string,
  urlPath: string,
): Promise<ServeResult> {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD" });
    res.end();
    return { status: 405, bytesSent: 0 };
  }

  const filePath = resolveSafePath(rootDir, urlPath);
  if (filePath === null) {
    res.writeHead(403);
    res.end();
    return { status: 403, bytesSent: 0 };
  }

  let stat;
  try {
    stat = await fs.stat(filePath);
  } catch {
    res.writeHead(404);
    res.end();
    return { status: 404, bytesSent: 0 };
  }

  if (!stat.isFile()) {
    res.writeHead(404);
    res.end();
    return { status: 404, bytesSent: 0 };
  }

  let headers: Record<string, string>;
  try {
    headers = buildFileHeaders(filePath, stat.size);
  } catch {
    res.writeHead(415);
    res.end();
    return { status: 415, bytesSent: 0 };
  }

  res.writeHead(200, headers);
  if (req.method === "HEAD") {
    res.end();
    return { status: 200, bytesSent: 0 };
  }

  const data = await fs.readFile(filePath);
  res.end(data);
  return { status: 200, bytesSent: data.byteLength };
}
