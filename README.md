# DreamTX

**Use your own AI.** A presentation app where *your* AI (ChatGPT, Claude, Gemini, any MCP client) builds decks in DreamTX through MCP — no API keys, no billing. The AI doesn't call us; we give the AI the tools.

## Stack

| Layer | Tech |
|---|---|
| App (UI) | Flutter (Android v1) |
| Core (engine) | Rust — one crate, two targets: native (FFI into Flutter) + wasm (inside the Worker) |
| Server | Cloudflare Worker (thin TS MCP glue + wasm engine), Durable Objects for deck state |
| Protocol | MCP over Streamable HTTP (+ SSE fallback) |

## Layout

```
core/crates/deck-core   Rust engine: deck model, DNAs, pacing governor,
                        layout solver, .pptx/.pdf export, FFI + wasm entry
app/                    Flutter app (Android). Run `flutter create .` once
                        (see app/README) — platform folders are CI-generated.
worker/                 Cloudflare Worker: MCP endpoint, pairing Registry DO,
                        per-deck Deck DO (state, version log, WS hibernation)
scripts/                Local dev helpers (build android .so, typecheck worker)
.github/workflows       CI: core tests (native+wasm), worker typecheck, APK release
```

## Design philosophy (the moat)

The AI never places pixels. It speaks **semantics** (archetypes: stat wall,
split, comparison, chart hero...); the Rust engine owns layout, type scale,
and color. Three curated deck DNAs ship in v1 — **Swiss editorial** (default),
**cinematic**, **magazine serif** — each with seeded per-deck variation, plus a
pacing governor (no same archetype twice in a row, density rhythm, whitespace
budget) so decks never look template-stamped.

## State of this scaffold (M0)

- Rust core: real model, 3 DNAs + variation, pacing, layout solver, pptx +
  pdf exporters, JSON command protocol, FFI + wasm exports, smoke tests.
- Worker: full MCP (initialize/tools list/call) over Streamable HTTP + SSE,
  pairing Registry DO (code+secret, TTL, attempt limiting), Deck DO with
  hibernating WebSocket broadcast and version log. Not yet deployed.
- Flutter: decks list, editor (canvas + filmstrip, text edit, archetype
  swap), DNA variant cycling, export via share sheet, pair sheet.
- CI: cargo test (native + wasm32), worker typecheck, APK build + Release.

Known v0.1 limits: PDF export is Latin-first (base-14 fonts, non-Latin is
transliterated; full font embedding/subsetting lands with CJK metrics in M2),
CJK glyph widths are approximated (metrics font is DejaVu), android platform
folders are generated in CI, APK is debug-signed.

## Milestones

- **M0** scaffold + green CI (this push)
- **M1** installable APK from GitHub Releases (editor + export, offline)
- **M2** Worker deployed (needs Cloudflare token) + MCP end-to-end = **v1**

## Local dev

```bash
# Rust core tests
cd core && cargo test
# wasm target
cargo build --target wasm32-unknown-unknown --features wasm --release
# Worker typecheck
cd worker && npm install && npx tsc --noEmit
# Flutter app (first time generates android/)
cd app && flutter create --org com.dreamtx . && flutter pub get
# Rust .so for android (needs NDK + cargo-ndk)
./scripts/build-android.sh
flutter run
```

Fonts bundled in `core/crates/deck-core/fonts/` are DejaVu (Bitstream Vera /
Public Domain license terms) — see `fonts/README.md`.
