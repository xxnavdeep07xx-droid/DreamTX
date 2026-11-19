/**
 * MCP command flow, end to end against a REAL local Worker (wrangler dev in
 * local/workerd mode — same bundling, same wasm rules as production):
 *
 *   health (wasm engine initialized — asserted, not assumed)
 *   → /pair creates a pairing (the app side)
 *   → MCP initialize + tools/list (the AI client handshake)
 *   → tools/call create_deck (stateless, runs the Rust wasm engine directly)
 *   → /decks/<id>/init pushes the deck into the Durable Object (the app side)
 *   → tools/call add_slide WITHOUT a deck arg (the DO injects stored state)
 *   → /decks/<id>/state shows the mutation + version bump (the app update leg)
 *
 * Run order matters: `npm run build:wasm` must have produced worker/wasm/
 * before this test starts (CI does; see package.json scripts).
 *
 * Not covered here — reported honestly: the production Cloudflare network
 * path (deploy, real global DO placement) and the app's WebSocket leg (the
 * app-side surface is covered by the Flutter suite; the DO's WebSocket
 * fan-out is exercised by wrangler's local workerd runtime only implicitly
 * through /state).
 */
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const WORKER_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BASE = process.env.TEST_BASE_URL ?? "http://127.0.0.1:8787";
const DECK_ID = "e2e_deck";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let child = null;
const logs = [];

before(async () => {
  child = spawn("npx", ["wrangler", "dev", "--local", "--port", "8787"], {
    cwd: WORKER_ROOT,
    detached: true, // own process group: workerd children die with us
    env: { ...process.env, WRANGLER_SEND_METRICS: "false", CI: "true" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (d) => logs.push(d.toString()));
  child.stderr.on("data", (d) => logs.push(d.toString()));
  // Readiness = /health answers. 120s budget: first wrangler dev start can
  // take a while in CI (workerd download already done by npm install).
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) break;
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) return;
    } catch {}
    await sleep(1000);
  }
  throw new Error(
    `wrangler dev did not become healthy within 120s. Last logs:\n${logs.slice(-40).join("")}`,
  );
});

after(() => {
  if (!child) return;
  try {
    process.kill(-child.pid, "SIGTERM"); // the whole group, workerd included
  } catch {
    child.kill("SIGTERM");
  }
});

const jsonHeaders = { "content-type": "application/json" };

/** Fail loudly AND informatively: a wrong status dumps the body plus the
 * tail of wrangler's own console — the cause of a surprise 404/500 is
 * always in one of the two. */
function expectStatus(what, expected, actual, respBody) {
  if (actual !== expected) {
    throw new Error(
      `${what}: expected HTTP ${expected}, got ${actual}; body: ` +
        `${JSON.stringify(respBody)}\nwrangler tail:\n${logs.slice(-30).join("")}`,
    );
  }
}

async function post(pathname, body) {
  const r = await fetch(`${BASE}${pathname}`, {
    method: "POST",
    headers: jsonHeaders,
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

async function get(pathname) {
  const r = await fetch(`${BASE}${pathname}`);
  return { status: r.status, body: await r.json().catch(() => null) };
}

/** One JSON-RPC call over the pairing URL. */
async function rpc(token, method, params) {
  const { status, body } = await post(`/p/${token}/mcp`, {
    jsonrpc: "2.0",
    id: Math.floor(Math.random() * 1e6),
    method,
    params,
  });
  assert.equal(status, 200, `rpc ${method} → HTTP ${status}`);
  return body;
}

test("engine is the real Rust wasm, observable on /health", async () => {
  const { status, body } = await get("/health");
  assert.equal(status, 200);
  assert.equal(body.ok, true);
  // The whole point of the P2 wiring: the fallback must not be silently
  // active. If this fails, wasm init broke — check the wrangler logs above.
  assert.equal(
    body.engine,
    "wasm",
    `expected the Rust wasm engine, got: ${JSON.stringify(body)}`,
  );
});

test("pairing → MCP handshake → create_deck → deck DO init → mutation → app-visible update", async () => {
  // -- the app side asks for a pairing -----------------------------------
  const pair = await post("/pair", { deckId: DECK_ID });
  expectStatus("/pair", 200, pair.status, pair.body);
  assert.equal(pair.body.ok, true, JSON.stringify(pair.body));
  const token = pair.body.token;
  assert.ok(token && token.includes("-"), `pairing token looks wrong: ${token}`);

  // -- the AI client handshake --------------------------------------------
  const init = await rpc(token, "initialize", {});
  assert.equal(init.result.protocolVersion, "2025-03-26");
  assert.equal(init.result.serverInfo.name, "dreamtx");
  const tools = await rpc(token, "tools/list", {});
  const names = tools.result.tools.map((t) => t.name);
  assert.ok(names.includes("add_slide"), `tools/list missing add_slide: ${names}`);
  assert.ok(names.includes("create_deck"));

  // -- create_deck: stateless tool, runs the wasm engine directly ----------
  const created = await rpc(token, "tools/call", {
    name: "create_deck",
    arguments: { title: "E2E Deck", family: "swiss_editorial" },
  });
  assert.equal(
    created.result.isError,
    undefined,
    `create_deck errored: ${created.result.content?.[0]?.text}`,
  );
  const deck = JSON.parse(created.result.content[0].text).deck;
  assert.ok(deck.id, "engine returned a deck");
  assert.equal(deck.version, 1);
  const slideCountBefore = deck.slides.length;
  assert.ok(slideCountBefore >= 1, "a fresh deck has at least a cover");

  // -- the app side pushes the deck into its Durable Object ----------------
  const initResp = await post(`/decks/${DECK_ID}/init`, { deck });
  expectStatus("deck DO init", 200, initResp.status, initResp.body);
  assert.equal(initResp.body.ok, true, JSON.stringify(initResp.body));
  assert.equal(initResp.body.version, 1);

  // -- the AI mutates WITHOUT passing the deck back: the DO injects state --
  const mutated = await rpc(token, "tools/call", {
    name: "add_slide",
    arguments: { archetype: "statement" },
  });
  assert.equal(
    mutated.result.isError,
    undefined,
    `add_slide errored: ${mutated.result.content?.[0]?.text}`,
  );
  assert.equal(mutated.result.engine, "wasm", "mutation answered by wasm");

  // -- the app side sees the update: version bumped, slide count grew -----
  const state = await get(`/decks/${DECK_ID}/state`);
  expectStatus("deck DO state", 200, state.status, state.body);
  assert.ok(state.body.version >= 2, `version did not bump: ${state.body.version}`);
  assert.equal(
    state.body.slides,
    slideCountBefore + 1,
    `expected ${slideCountBefore + 1} slides after the AI's add_slide`,
  );
  assert.ok(
    state.body.log.some((e) => e.op === "add_slide" && e.actor === "ai"),
    `the audit log records the AI's mutation: ${JSON.stringify(state.body.log)}`,
  );
});

test("wrong pairing token is rejected", async () => {
  const { status, body } = await post("/p/0000-DEADBEEF/mcp", {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {},
  });
  assert.equal(status, 401);
  // The 401 body carries the reason, not an ok flag.
  assert.ok(body.error, `expected an error body, got: ${JSON.stringify(body)}`);
});
