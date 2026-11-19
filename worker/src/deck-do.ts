/**
 * Deck Durable Object — the authoritative home of one deck.
 *
 * Responsibilities:
 *  - state + monotonic version (the sync backbone for offline clients)
 *  - command execution via the engine bridge (Rust wasm when bundled)
 *  - hibernating WebSocket fan-out (editors watch the AI build live; sockets
 *    cost nothing while idle)
 *  - capped audit log ("ChatGPT modified slide 3 at 14:02")
 *
 * Pairing binds an MCP session to exactly one of these objects.
 */

import { ensureEngine, runCommand } from "./engine";
import type { Json } from "./env";

const LOG_CAP = 200;

interface LogEntry {
  v: number;
  actor: string;
  op: string;
  summary: string;
  ts: number;
}

interface DeckState {
  deck: Json | null;
  version: number;
  log: LogEntry[];
}

export class DeckDO implements DurableObject {
  private state: DeckState = { deck: null, version: 0, log: [] };

  constructor(private ctx: DurableObjectState, private env: unknown) {
    void this.env;
    this.state = { deck: null, version: 0, log: [] };
    // Cheap heartbeat while a socket is hibernating.
    this.ctx.setWebSocketAutoResponse?.(
      new WebSocketRequestResponsePair(JSON.stringify({ type: "ping" }), JSON.stringify({ type: "pong" })),
    );
  }

  async fetch(request: Request): Promise<Response> {
    await this.load();
    // DOs can live in a different isolate than the entry worker: each one
    // wires the wasm engine for its own isolate, idempotently.
    await ensureEngine();
    const url = new URL(request.url);

    if (url.pathname === "/ws") {
      if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
        return new Response("expected websocket", { status: 400 });
      }
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].send(JSON.stringify({ type: "hello", version: this.state.version }));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    if (request.method === "POST" && url.pathname === "/init") {
      const body = (await request.json<{ deck?: Json }>()) ?? {};
      if (!body.deck) return json({ ok: false, error: "deck required" }, 400);
      this.state.deck = body.deck;
      this.state.version += 1;
      await this.save();
      await this.broadcast({ type: "reset", version: this.state.version, deck: this.state.deck });
      return json({ ok: true, version: this.state.version });
    }

    if (request.method === "GET" && (url.pathname === "/state" || url.pathname === "/")) {
      return json({
        ok: true,
        version: this.state.version,
        deck: this.state.deck,
        slides: slideCount(this.state.deck),
        sessions: this.ctx.getWebSockets().length,
        log: this.state.log.slice(-20),
      });
    }

    if (request.method === "POST" && url.pathname === "/op") {
      const body = (await request.json<{ command?: Record<string, Json>; actor?: string }>()) ?? {};
      if (!body.command) return json({ ok: false, error: "command required" }, 400);
      const cmd = { ...body.command };
      if (this.state.deck && !("deck" in cmd)) {
        (cmd as Record<string, Json>)["deck"] = this.state.deck;
      }
      const result = await runCommand(cmd as Record<string, Json>);
      const newDeck = result.ok && typeof result.data === "object" && result.data !== null
        ? ((result.data as Record<string, Json>)["deck"] ?? null)
        : null;
      if (result.ok && newDeck) {
        this.state.deck = newDeck;
        this.state.version += 1;
        this.state.log.push({
          v: this.state.version,
          actor: body.actor ?? "ai",
          op: String(body.command.op ?? "?"),
          summary: `${String(body.command.op ?? "?")} -> ${slideCount(newDeck)} slides`,
          ts: Date.now(),
        });
        if (this.state.log.length > LOG_CAP) this.state.log.splice(0, this.state.log.length - LOG_CAP);
        await this.save();
        await this.broadcast({ type: "update", version: this.state.version, deck: this.state.deck, actor: body.actor ?? "ai" });
      }
      return json(result, result.ok ? 200 : 400);
    }

    if (request.method === "POST" && url.pathname === "/event") {
      const body = (await request.json<{ event?: Json }>()) ?? {};
      await this.broadcast({ type: "event", event: body.event ?? null });
      return json({ ok: true });
    }

    return json({ ok: false, error: "not found" }, 404);
  }

  /** Hibernation callback: client messages (subscribe w/ catch-up). */
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    let msg: { type?: string; since_version?: number };
    try {
      msg = JSON.parse(typeof message === "string" ? message : "[invalid]") ?? {};
    } catch {
      return;
    }
    if (msg.type === "subscribe") {
      // Versioned catch-up: mobile sockets die constantly; clients resume
      // from their last seen version.
      ws.send(JSON.stringify({
        type: "snapshot",
        version: this.state.version,
        deck: this.state.deck,
        upToDate: typeof msg.since_version === "number" && msg.since_version === this.state.version,
      }));
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): Promise<void> {
    void ws;
    void code;
    void reason;
    void wasClean;
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    void ws;
    void error;
  }

  private async load(): Promise<void> {
    const deck = await this.ctx.storage.get<Json>("deck");
    const version = await this.ctx.storage.get<number>("version");
    const log = await this.ctx.storage.get<LogEntry[]>("log");
    this.state = { deck: deck ?? null, version: version ?? 0, log: log ?? [] };
  }

  private async save(): Promise<void> {
    await this.ctx.storage.put("deck", this.state.deck);
    await this.ctx.storage.put("version", this.state.version);
    await this.ctx.storage.put("log", this.state.log);
  }

  private async broadcast(payload: Json): Promise<void> {
    const text = JSON.stringify(payload);
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(text);
      } catch {
        // dead socket: hibernation reaping handles it
      }
    }
  }
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function slideCount(deck: Json | null): number {
  if (typeof deck !== "object" || deck === null) return 0;
  const slides = (deck as Record<string, Json>)["slides"];
  return Array.isArray(slides) ? slides.length : 0;
}
