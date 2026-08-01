import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";

import { resolveSafePath } from "../src/static_file_handler.js";

const root = path.resolve("/tmp/image-analysis-server-test-root");

test("resolveSafePath resolve um caminho relativo simples", () => {
  const resolved = resolveSafePath(root, "/manifest.json");
  assert.equal(resolved, path.join(root, "manifest.json"));
});

test("resolveSafePath resolve caminhos aninhados", () => {
  const resolved = resolveSafePath(root, "/variants/image_001__original__jpeg__q70.jpg");
  assert.equal(
    resolved,
    path.join(root, "variants", "image_001__original__jpeg__q70.jpg"),
  );
});

test("resolveSafePath rejeita travessia de diretório com ..", () => {
  assert.equal(resolveSafePath(root, "/../secret.txt"), null);
  assert.equal(resolveSafePath(root, "/variants/../../secret.txt"), null);
  assert.equal(resolveSafePath(root, "/variants/%2e%2e/secret.txt"), null);
});

test("resolveSafePath rejeita bytes nulos", () => {
  assert.equal(resolveSafePath(root, "/manifest.json%00.txt"), null);
});

test("resolveSafePath rejeita o próprio diretório raiz", () => {
  assert.equal(resolveSafePath(root, "/"), null);
  assert.equal(resolveSafePath(root, ""), null);
});

test("resolveSafePath rejeita URL malformada", () => {
  assert.equal(resolveSafePath(root, "/%"), null);
});
