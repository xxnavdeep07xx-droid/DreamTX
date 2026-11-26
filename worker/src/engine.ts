/**
 * Engine bridge. The dream is ONE engine everywhere: the Rust deck-core
 * compiled to wasm, called from this Worker with the exact same JSON command
 * protocol the Flutter app speaks over FFI.
 *
 * The wasm module is bundled: `npm run build:wasm` (wasm-pack --target web)
 * compiles deck-core into worker/wasm/, the generated JS glue is imported
 * below, and [ensureEngine] wires it up exactly once per isolate. Until the
 * glue is present the structural commands fall back to a tiny pure-TS
 * mirror so the MCP surface is fully exercisable end-to-end even in a
 * checkout without a Rust toolchain — but that fallback is observable
 * ([engineModeNow], /health, a console.warn on init failure), never silent.
 * Layout/export/pacing require the Rust engine — they report a clean error
 * until then.
 */
import init, { command as wasmCommand } from "../wasm/dreamtx.js";
import wasmModule from "../wasm/dreamtx_bg.wasm";
import type { Json } from "./env";

export interface EngineResult {
  ok: boolean;
  data?: unknown;
  error?: string;
}

let wasmCommand_: ((req: string) => string) | null = null;

export function setWasm(fn: (req: string) => string): void {
  wasmCommand_ = fn;
}

export function wasmAvailable(): boolean {
  return wasmCommand_ !== null;
}

export type EngineMode = "wasm" | "ts-fallback";

let engineInit: Promise<EngineMode> | null = null;

/**
 * Initialize the Rust wasm engine exactly once per isolate. Safe to await
 * from every request (including concurrent ones — they share the single
 * init) and from the Deck Durable Object. A failed init logs a warning and
 * leaves the TS fallback active — visibly, via [engineModeNow] and /health.
 */
export function ensureEngine(): Promise<EngineMode> {
  if (!engineInit) {
    engineInit = (async () => {
      try {
        await init(wasmModule);
        setWasm((req: string) => wasmCommand(req));
        console.log("[dreamtx-engine] wasm engine ready (deck-core)");
        return "wasm" as const;
      } catch (e) {
        console.warn(
          "[dreamtx-engine] wasm init failed — TS fallback active:",
          String(e),
        );
        return "ts-fallback" as const;
      }
    })();
  }
  return engineInit;
}

/** Which engine is answering commands in this isolate right now. */
export function engineModeNow(): EngineMode {
  return wasmAvailable() ? "wasm" : "ts-fallback";
}

export async function runCommand(cmd: Record<string, Json>): Promise<EngineResult> {
  if (wasmCommand_) {
    try {
      const resp = JSON.parse(wasmCommand_(JSON.stringify(cmd))) as Record<
        string,
        unknown
      >;
      // The Rust core answers FLAT: { ok, deck?, layout?, ... } / { ok:false,
      // error }. The TS fallback wraps its payload in `data`. Normalize the
      // wasm shape into the EngineResult contract so callers never see two
      // different response grammars.
      if (resp.ok === true) {
        const data = { ...(resp as Record<string, unknown>) };
        delete data.ok;
        return (Object.keys(data).length > 0
          ? { ok: true, data }
          : { ok: true }) as EngineResult;
      }
      return {
        ok: false,
        error: String(resp.error ?? "engine reported failure without an error"),
      };
    } catch (e) {
      return { ok: false, error: `engine crashed: ${String(e)}` };
    }
  }
  return tsFallback(cmd);
}

// ---- pure-TS structural fallback (M0) -------------------------------------

const ARCHETYPES = new Set([
  "cover", "agenda", "section", "statement", "stat_wall",
  "split", "comparison", "chart_hero", "closing",
]);

interface SlideLike {
  id: string;
  [k: string]: Json | undefined;
}

interface DeckLike {
  id: string;
  title: string;
  version: number;
  dna: { family: string; seed: number };
  slides: SlideLike[];
}

function asDeck(v: Json | undefined): DeckLike | null {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return null;
  const d = v as unknown as DeckLike;
  return Array.isArray(d.slides) && typeof d.id === "string" && typeof d.version === "number" ? d : null;
}

function slideId(deckId: string, count: number): string {
  return `s_${deckId.slice(0, 6)}_${count + 1}_${Math.random().toString(36).slice(2, 7)}`;
}

function tsFallback(cmd: Record<string, Json>): EngineResult {
  const op = String(cmd.op ?? "");
  const deck = asDeck(cmd.deck);
  switch (op) {
    case "meta":
      return {
        ok: true,
        data: {
          archetypes: [...ARCHETYPES],
          families: ["swiss_editorial", "cinematic", "magazine_serif", "bold", "pastel"],
        },
      };
    case "new_deck": {
      const title = typeof cmd.title === "string" && cmd.title ? cmd.title : "Untitled";
      const family = typeof cmd.family === "string" ? cmd.family : "swiss_editorial";
      const id = `d${Math.random().toString(16).slice(2, 10)}`;
      const deckOut: DeckLike = {
        id,
        title,
        version: 1,
        dna: { family, seed: Date.now() },
        slides: [
          { id: slideId(id, 0), archetype: "cover", content: { kind: "cover", kicker: null, title, subtitle: null } },
        ],
      };
      return { ok: true, data: { deck: deckOut } };
    }
    case "add_slide": {
      if (!deck) return { ok: false, error: "invalid deck" };
      const archetype = String(cmd.archetype ?? "");
      if (!ARCHETYPES.has(archetype)) return { ok: false, error: `unknown archetype '${archetype}'` };
      const content = cmd.content ?? { kind: archetype };
      const slide: SlideLike = {
        id: slideId(deck.id, deck.slides.length),
        archetype,
        content: typeof content === "object" && content !== null ? content : { kind: archetype },
      };
      deck.slides = [...deck.slides, slide];
      deck.version += 1;
      return { ok: true, data: { deck } };
    }
    case "update_slide": {
      if (!deck) return { ok: false, error: "invalid deck" };
      const idx = deck.slides.findIndex((s) => s.id === cmd.slide_id);
      if (idx < 0) return { ok: false, error: "slide not found" };
      const archetype = String(cmd.archetype ?? deck.slides[idx].archetype ?? "");
      const content = cmd.content;
      if (typeof content !== "object" || content === null) return { ok: false, error: "content required" };
      deck.slides[idx] = { id: String(cmd.slide_id), archetype, content: content as Record<string, Json> };
      deck.version += 1;
      return { ok: true, data: { deck } };
    }
    case "delete_slide": {
      if (!deck) return { ok: false, error: "invalid deck" };
      const before = deck.slides.length;
      deck.slides = deck.slides.filter((s) => s.id !== cmd.slide_id);
      if (deck.slides.length === before) return { ok: false, error: "slide not found" };
      deck.version += 1;
      return { ok: true, data: { deck } };
    }
    case "move_slide": {
      if (!deck) return { ok: false, error: "invalid deck" };
      const idx = deck.slides.findIndex((s) => s.id === cmd.slide_id);
      const to = Number(cmd.to_index);
      if (idx < 0 || !Number.isInteger(to) || to < 0 || to >= deck.slides.length) {
        return { ok: false, error: "slide or index out of range" };
      }
      const [s] = deck.slides.splice(idx, 1);
      deck.slides.splice(to, 0, s);
      deck.version += 1;
      return { ok: true, data: { deck } };
    }
    case "get_layout":
    case "pacing":
    case "export_pptx":
    case "export_pdf":
      return {
        ok: false,
        error: "This operation needs the Rust wasm engine, which is not bundled in M0. It lands in M1.",
      };
    default:
      return { ok: false, error: `unknown op '${op}'` };
  }
}
