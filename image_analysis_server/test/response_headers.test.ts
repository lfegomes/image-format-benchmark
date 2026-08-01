import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildFileHeaders,
  contentTypeFor,
  NO_CACHE_HEADERS,
} from "../src/response_headers.js";

test("NO_CACHE_HEADERS desabilita cache, pragma e expiração", () => {
  assert.equal(
    NO_CACHE_HEADERS["Cache-Control"],
    "no-store, no-cache, must-revalidate, max-age=0",
  );
  assert.equal(NO_CACHE_HEADERS["Pragma"], "no-cache");
  assert.equal(NO_CACHE_HEADERS["Expires"], "0");
});

test("contentTypeFor resolve tipos suportados", () => {
  assert.equal(contentTypeFor("manifest.json"), "application/json; charset=utf-8");
  assert.equal(contentTypeFor("references/x__reference1080.png"), "image/png");
  assert.equal(contentTypeFor("variants/x__original__jpeg__q70.jpg"), "image/jpeg");
  assert.equal(contentTypeFor("variants/x__original__webp__q70.webp"), "image/webp");
});

test("contentTypeFor rejeita extensões fora de escopo", () => {
  assert.throws(() => contentTypeFor("variants/x.gif"));
  assert.throws(() => contentTypeFor("variants/x.svg"));
});

test("buildFileHeaders inclui Content-Length, Content-Type e sem cache", () => {
  const headers = buildFileHeaders("variants/x.webp", 12345);
  assert.equal(headers["Content-Type"], "image/webp");
  assert.equal(headers["Content-Length"], "12345");
  assert.equal(headers["Cache-Control"], "no-store, no-cache, must-revalidate, max-age=0");
  assert.equal(headers["Content-Encoding"], undefined);
});
