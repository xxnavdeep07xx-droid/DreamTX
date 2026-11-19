/**
 * DreamTX MCP endpoint.
 *
 * Pairing URLs carry the credential: https://<host>/p/<CODE>-<SECRET>/mcp
 * (no-auth custom connectors can't send headers, so the URL must be enough).
 *
 * Streamable HTTP (POST JSON-RPC) is primary; GET/SSE channels and mcp-remote
 * (stdio bridge) both work against this same surface. The endpoint is
 * stateless per request: sessions live in the deck's Durable Object.
 */

import { PairingRegistry } from "./registry-do";
import { DeckDO } from "./deck-do";
import { TOOLS, toolToCommand } from "./tools";
import { ensureEngine, engineModeNow, runCommand } from "./engine";
import type { Env, Json, RpcRequest, RpcResponse } from "./env";

export { PairingRegistry, DeckDO };

const MCP_PROTOCOL_VERSION = "2025-03-26";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Every request enters with the Rust wasm engine wired (idempotent, one
    // init per isolate, safe under concurrency). A failed init is logged and
    // observable on /health — never silent.
    const engine = await ensureEngine();
    const url = new URL(request.url);

    // ---- health / pairing (app-facing) -----------------------------------
    if (url.pathname === "/health") {
      return json({
        ok: true,
        service: "dreamtx-worker",
        mcp: "streamable-http+sse",
        engine,
        engineReady: true,
      });
    }

    // The app asks the registry for a pairing token for a deck.
    if (url.pathname === "/pair" && request.method === "POST") {
      return registryFetch(env, new Request("https://registry/create", {
        method: "POST",
        body: await request.text(),
      }));
    }
    if (url.pathname === "/pair/revoke" && request.method === "POST") {
      return registryFetch(env, new Request("https://registry/revoke", {
        method: "POST",
        body: await request.text(),
      }));
    }

    // ---- MCP surface -------------------------------------------------------
    const mcpMatch = url.pathname.match(/^\/p\/([0-9A-Z-]+)\/mcp$/i);
    if (mcpMatch) {
      const token = mcpMatch[1];
      const claimed = await claim(env, token);
      if (!claimed.ok) return json({ error: claimed.error }, 401);
      const deckId = claimed.deckId!;

      if (request.method === "DELETE") {
        return new Response(null, { status: 204 });
      }
      if (request.method === "POST") {
        return mcpPost(request, env, deckId);
      }
      if (request.method === "GET") {
        // Stateless server: no server-initiated SSE stream. Live deck
        // streaming happens on the deck DO WebSocket (app route below).
        return new Response("SSE channel not used; use POST (Streamable HTTP)", {
          status: 405,
          headers: { allow: "POST, DELETE" },
        });
      }
      return new Response("method not allowed", { status: 405 });
    }

    // ---- app sync surface (deck DO: state + websocket) ---------------------
    const deckMatch = url.pathname.match(/^\/decks\/([^/]+)(\/.*)?$/);
    if (deckMatch) {
      const deckId = deckMatch[1];
      const sub = deckMatch[2] ?? "/state";
      const stub = env.DECKS.get(env.DECKS.idFromName(deckId));
      return stub.fetch(`https://deck${sub}${url.search}`);
    }

    return json({ ok: false, error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;

// ---- MCP JSON-RPC ---------------------------------------------------------

async function mcpPost(request: Request, env: Env, deckId: string): Promise<Response> {
  let rpc: RpcRequest;
  try {
    rpc = (await request.json<RpcRequest>()) as RpcRequest;
  } catch {
    return rpcError(null, -32700, "parse error");
  }

  // Notifications (no id): initialized, cancelled — acknowledge silently.
  if (rpc.id === undefined) {
    return new Response(null, { status: 202 });
  }

  switch (rpc.method) {
    case "initialize":
      return rpcResult(rpc.id, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "dreamtx", version: "0.1.0" },
      });
    case "notifications/initialized":
      return new Response(null, { status: 202 });
    case "ping":
      return rpcResult(rpc.id, {});
    case "tools/list":
      return rpcResult(rpc.id, { tools: TOOLS } as unknown as Json);
    case "tools/call": {
      const params = (rpc.params ?? {}) as { name?: string; arguments?: Record<string, Json> };
      const name = String(params.name ?? "");
      if (!TOOLS.some((t) => t.name === name)) {
        return rpcError(rpc.id, -32602, `unknown tool '${name}'`);
      }
      const args = params.arguments ?? {};
      const actor = "ai";

      // Deck-carrying tools run against the deck DO (state + broadcast);
      // stateless tools run the engine directly.
      const needsDeck = name !== "deck_meta" && name !== "create_deck";
      if (needsDeck) {
        const deck = (args as { deck?: Json }).deck;
        const stub = env.DECKS.get(env.DECKS.idFromName(deckId));
        const cmd = toolToCommand(name, args as Record<string, unknown>) ?? {};
        const resp = await stub.fetch("https://deck/op", {
          method: "POST",
          body: JSON.stringify({ command: { ...cmd, deck: deck ?? undefined }, actor }),
        });
        const result = (await resp.json<Record<string, Json>>()) ?? {};
        if (result.ok) {
          return rpcResult(rpc.id, {
            content: [{ type: "text", text: JSON.stringify(result.data ?? {}) }],
            engine: engineModeNow(),
          } as unknown as Json);
        }
        return rpcResult(rpc.id, {
          content: [{ type: "text", text: `Error: ${String(result.error ?? "unknown")}` }],
          isError: true,
          engine: engineModeNow(),
        } as unknown as Json);
      }

      const cmd = toolToCommand(name, args as Record<string, unknown>) ?? {};
      const result = await runCommand(cmd as Record<string, Json>);
      if (result.ok) {
        return rpcResult(rpc.id, {
          content: [{ type: "text", text: JSON.stringify(result.data ?? {}) }],
          engine: engineModeNow(),
        } as unknown as Json);
      }
      return rpcResult(rpc.id, {
        content: [{ type: "text", text: `Error: ${String(result.error ?? "unknown")}` }],
        isError: true,
        engine: engineModeNow(),
      } as unknown as Json);
    }
    default:
      return rpcError(rpc.id, -32601, `method not found: ${rpc.method}`);
  }
}

function rpcResult(id: Json | undefined, result: Json): Response {
  const body: RpcResponse = { jsonrpc: "2.0", id, result };
  return new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function rpcError(id: Json | undefined, code: number, message: string): Response {
  const body: RpcResponse = { jsonrpc: "2.0", id, error: { code, message } };
  return new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

// ---- helpers ---------------------------------------------------------------

async function claim(env: Env, token: string): Promise<{ ok: boolean; error?: string; deckId?: string }> {
  const stub = env.REGISTRY.get(env.REGISTRY.idFromName("global"));
  const resp = await stub.fetch("https://registry/claim", {
    method: "POST",
    body: JSON.stringify({ token }),
  });
  return (await resp.json<{ ok: boolean; error?: string; deckId?: string }>()) ?? { ok: false };
}

async function registryFetch(env: Env, req: Request): Promise<Response> {
  const stub = env.REGISTRY.get(env.REGISTRY.idFromName("global"));
  return stub.fetch(req);
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
