import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

import { createServer } from "../src/server.js";

let baseUrl: string;
let server: ReturnType<typeof createServer>;
let rootDir: string;

before(async () => {
  rootDir = mkdtempSync(path.join(tmpdir(), "image-analysis-server-"));
  writeFileSync(
    path.join(rootDir, "manifest.json"),
    JSON.stringify({ schemaVersion: 1, variants: [] }),
  );
  const variantsDir = path.join(rootDir, "variants");
  await import("node:fs/promises").then((fs) => fs.mkdir(variantsDir));
  writeFileSync(path.join(variantsDir, "fake.jpg"), Buffer.from([0xff, 0xd8, 0xff]));

  server = createServer(rootDir);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("Endereço do servidor inesperado");
  }
  baseUrl = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
  rmSync(rootDir, { recursive: true, force: true });
});

test("GET /health responde 200 com corpo JSON e sem cache", async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store, no-cache, must-revalidate, max-age=0");
  const body = await response.json();
  assert.deepEqual(body, { status: "ok" });
});

test("GET /manifest.json serve o arquivo com Content-Type correto", async () => {
  const response = await fetch(`${baseUrl}/manifest.json`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
  const body = (await response.json()) as { schemaVersion: number };
  assert.equal(body.schemaVersion, 1);
});

test("GET /variants/fake.jpg serve o arquivo com Content-Length correto", async () => {
  const response = await fetch(`${baseUrl}/variants/fake.jpg`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/jpeg");
  assert.equal(response.headers.get("content-length"), "3");
});

test("GET de arquivo inexistente responde 404", async () => {
  const response = await fetch(`${baseUrl}/variants/does-not-exist.jpg`);
  assert.equal(response.status, 404);
});

test("rota desconhecida responde 404", async () => {
  const response = await fetch(`${baseUrl}/unknown`);
  assert.equal(response.status, 404);
});

test("POST em rota estática responde 405", async () => {
  const response = await fetch(`${baseUrl}/manifest.json`, { method: "POST" });
  assert.equal(response.status, 405);
});

test("requisição condicional (If-None-Match) ainda recebe 200 com corpo completo", async () => {
  const response = await fetch(`${baseUrl}/manifest.json`, {
    headers: { "If-None-Match": '"anything"', "If-Modified-Since": new Date().toUTCString() },
  });
  assert.equal(response.status, 200);
  assert.ok((await response.text()).length > 0);
});
