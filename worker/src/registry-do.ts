/**
 * Pairing Registry Durable Object.
 *
 * One global DO (idFromName("global")) holding:
 *   token -> { deckId, secret, expiresAt, attempts, claimed }
 *
 * Token format: "<4-digit code>-<8-char secret>", e.g. 8492-K7X2Q9M2.
 * The secret lives in the pairing URL, so the MCP endpoint needs zero OAuth.
 * Lazy TTL: claims check expiry at read time; nothing bills while idle.
 */

const TTL_MS = 15 * 60 * 1000; // 15 minutes
const MAX_ATTEMPTS = 5;

interface Pairing {
  deckId: string;
  code: string;
  secret: string;
  expiresAt: number;
  attempts: number;
  claimed: boolean;
}

interface RegistryState {
  pairings: Record<string, Pairing>; // keyed by code (the human part)
}

export class PairingRegistry implements DurableObject {
  private state: RegistryState = { pairings: {} };

  constructor(private ctx: DurableObjectState, private env: unknown) {
    void env;
    void this.ctx;
    this.state = { pairings: {} };
    // Restore from storage (lazy-loaded in fetch to keep constructor cheap).
  }

  private async load(): Promise<void> {
    const stored = await this.ctx.storage.get<RegistryState>("state");
    if (stored) this.state = stored;
  }

  private async save(): Promise<void> {
    await this.ctx.storage.put("state", this.state);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    await this.load();
    this.sweep();

    if (request.method === "POST" && url.pathname === "/create") {
      const body = (await request.json<{ deckId?: string }>()) ?? {};
      if (!body.deckId) return json({ ok: false, error: "deckId required" }, 400);
      // revoke any live pairing for this deck
      for (const [code, p] of Object.entries(this.state.pairings)) {
        if (p.deckId === body.deckId) delete this.state.pairings[code];
      }
      const code = randomDigits(4);
      const secret = randomSecret(8);
      this.state.pairings[code] = {
        deckId: body.deckId,
        code,
        secret,
        expiresAt: Date.now() + TTL_MS,
        attempts: 0,
        claimed: false,
      };
      await this.save();
      return json({ ok: true, code, secret, token: `${code}-${secret}`, expiresInMs: TTL_MS });
    }

    // Resolve a full token (code-secret) to its deck. Burns an attempt on
    // failure so typing wrong codes can't brute-force the secret.
    if (request.method === "POST" && url.pathname === "/claim") {
      const body = (await request.json<{ token?: string }>()) ?? {};
      const token = String(body.token ?? "");
      const [code, secret] = token.split("-");
      const p = code ? this.state.pairings[code] : undefined;
      if (!p || p.expiresAt < Date.now()) {
        return json({ ok: false, error: "pairing expired or unknown — generate a new code in the app" }, 404);
      }
      if (secret !== p.secret) {
        p.attempts += 1;
        if (p.attempts >= MAX_ATTEMPTS) {
          delete this.state.pairings[code!];
          await this.save();
          return json({ ok: false, error: "too many failed attempts — pairing invalidated" }, 403);
        }
        await this.save();
        return json({ ok: false, error: "invalid pairing token" }, 401);
      }
      return json({ ok: true, deckId: p.deckId, claimed: p.claimed });
    }

    if (request.method === "POST" && url.pathname === "/revoke") {
      const body = (await request.json<{ deckId?: string }>()) ?? {};
      for (const [code, p] of Object.entries(this.state.pairings)) {
        if (p.deckId === body.deckId) delete this.state.pairings[code];
      }
      await this.save();
      return json({ ok: true });
    }

    return json({ ok: false, error: "not found" }, 404);
  }

  /** Drop expired pairings; persist only when something changed. */
  private sweep(): void {
    const now = Date.now();
    let changed = false;
    for (const [code, p] of Object.entries(this.state.pairings)) {
      if (p.expiresAt < now) {
        delete this.state.pairings[code];
        changed = true;
      }
    }
    if (changed) void this.ctx.storage.put("state", this.state);
  }
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function randomDigits(n: number): string {
  let s = "";
  for (let i = 0; i < n; i++) s += Math.floor(Math.random() * 10);
  return s;
}

function randomSecret(n: number): string {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no ambiguous chars
  let s = "";
  for (let i = 0; i < n; i++) s += alphabet[Math.floor(Math.random() * alphabet.length)];
  return s;
}
