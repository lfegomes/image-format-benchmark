import http from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";

import { NO_CACHE_HEADERS } from "./response_headers.js";
import { parseServerConfig } from "./server_config.js";
import { serveStaticFile } from "./static_file_handler.js";

interface RequestLogEntry {
  method: string;
  path: string;
  status: number;
  bytesSent: number;
  durationMs: number;
}

function logRequest(entry: RequestLogEntry): void {
  const timestamp = new Date().toISOString();
  console.log(
    `${timestamp} ${entry.method} ${entry.path} ${entry.status} ` +
      `${entry.bytesSent}B ${entry.durationMs.toFixed(1)}ms`,
  );
}

function handleHealth(
  req: IncomingMessage,
  res: ServerResponse,
): { status: number; bytesSent: number } {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD", ...NO_CACHE_HEADERS });
    res.end();
    return { status: 405, bytesSent: 0 };
  }

  const body = JSON.stringify({ status: "ok" });
  const bytes = Buffer.byteLength(body);
  res.writeHead(200, {
    ...NO_CACHE_HEADERS,
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": String(bytes),
  });

  if (req.method === "HEAD") {
    res.end();
    return { status: 200, bytesSent: 0 };
  }

  res.end(body);
  return { status: 200, bytesSent: bytes };
}

// Node fecha conexões keep-alive ociosas após keepAliveTimeout (padrão:
// 5000ms). O HttpClient do Dart, por padrão, mantém conexões no pool por
// até 15s (idleTimeout) antes de descartá-las. Se o servidor fechar uma
// conexão antes do cliente perceber que ela está morta, a próxima
// requisição naquele socket reaproveitado recebe um reset de conexão —
// um candidato forte para falhas "relacionadas a HTTP" intermitentes numa
// rodada de 720 tarefas sequenciais, especialmente se alguma tarefa levar
// mais tempo que o normal entre o fim de um download e o início do
// próximo (decodificação/SSIM mais lentos em aparelhos mais fracos).
// Mantemos aqui uma folga bem maior que o idleTimeout configurado em
// `image_analysis_app/lib/benchmark/network/image_downloader.dart`, para
// que o cliente sempre descarte conexões ociosas antes que o servidor as
// feche por baixo dele.
const KEEP_ALIVE_TIMEOUT_MS = 65_000;
const HEADERS_TIMEOUT_MS = 66_000;

export function createServer(rootDir: string): http.Server {
  const server = http.createServer((req, res) => {
    void handleRequest(req, res, rootDir);
  });
  server.keepAliveTimeout = KEEP_ALIVE_TIMEOUT_MS;
  server.headersTimeout = HEADERS_TIMEOUT_MS;
  return server;
}

async function handleRequest(
  req: IncomingMessage,
  res: ServerResponse,
  rootDir: string,
): Promise<void> {
  const startedAt = process.hrtime.bigint();
  const host = req.headers.host ?? "localhost";
  const url = new URL(req.url ?? "/", `http://${host}`);
  const pathname = url.pathname;

  let status: number;
  let bytesSent: number;

  try {
    if (pathname === "/health") {
      ({ status, bytesSent } = handleHealth(req, res));
    } else if (
      pathname === "/manifest.json" ||
      pathname.startsWith("/references/") ||
      pathname.startsWith("/variants/")
    ) {
      ({ status, bytesSent } = await serveStaticFile(
        req,
        res,
        rootDir,
        pathname,
      ));
    } else {
      res.writeHead(404, NO_CACHE_HEADERS);
      res.end();
      status = 404;
      bytesSent = 0;
    }
  } catch (error) {
    if (!res.headersSent) {
      res.writeHead(500, NO_CACHE_HEADERS);
    }
    res.end();
    status = 500;
    bytesSent = 0;
    console.error(error);
  }

  const durationMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
  logRequest({
    method: req.method ?? "-",
    path: pathname,
    status,
    bytesSent,
    durationMs,
  });
}

function main(): void {
  const config = parseServerConfig(process.argv.slice(2));
  const server = createServer(config.rootDir);

  server.listen(config.port, config.host, () => {
    console.log(
      `Servidor de benchmark ouvindo em http://${config.host}:` +
        `${config.port}/ (root: ${config.rootDir})`,
    );
  });
}

const isMainModule =
  process.argv[1] !== undefined &&
  import.meta.url === new URL(process.argv[1], "file:").href;

if (isMainModule) {
  main();
}
