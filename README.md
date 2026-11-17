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

## What's in the app (v0.2.1)

**Decks home** — editorial deck grid; New deck button in the masthead;
long-press a deck card for open / rename / delete; immersive full-screen
mode (system bars hidden, edge-swipe to reveal).

**Editor (per deck)** — canvas + filmstrip; add / duplicate / reorder /
delete slides (long-press a thumbnail); full per-slide content forms for
all 9 archetypes (cover, agenda, section, statement, stat wall, split,
comparison, chart hero, closing); design family (DNA) switcher; undo/redo
(60 steps); deck rename.

**Design mode** (v0.2, editor toolbar) — 36 preset shapes + freeform
scribble; move / resize / rotate handles with 15-degree snap and smart
guides (snap to slide edges, centers, other objects); fills: solid,
linear + radial gradient; stroke: width, dash styles, start/end
arrowheads; effects: shadow, glow, opacity; boolean ops (union /
subtract / intersect — convex shapes); group / ungroup, lock, 6-way align,
layers panel (reorder / lock / delete); components: save a selection as a
reusable component, place it on any slide, update it globally. Objects
export 1:1 into PPTX and PDF.

**Export** — .pptx and .pdf via the share sheet.

**AI via MCP** — pairing sheet ready; goes live when the Worker deploys (M2).

Release APKs are signed with a release keystore (stored as GitHub Actions
secrets). Installs from releases before v0.2.1 were debug-signed — uninstall
those before installing v0.2.1+ (Android refuses updates across signers).

## State of this scaffold (M1 done)

- Rust core: real model, 3 DNAs + variation, pacing, layout solver, pptx +
  pdf exporters, JSON command protocol, FFI + wasm exports, smoke tests.
- Worker: full MCP (initialize/tools list/call) over Streamable HTTP + SSE,
  pairing Registry DO (code+secret, TTL, attempt limiting), Deck DO with
  hibernating WebSocket broadcast and version log. Not yet deployed.
- Flutter: decks list, editor (canvas + filmstrip, full content editing,
  design mode with the vector layer above), DNA variant cycling, export via
  share sheet, pair sheet.
- CI: cargo test (native + wasm32), worker typecheck, APK build + Release
  (release-signed since v0.2.1).

Known v0.2 limits: PDF export is Latin-first (base-14 fonts, non-Latin is
transliterated; full font embedding/subsetting lands with CJK metrics in M2),
CJK glyph widths are approximated (metrics font is DejaVu), android platform
folders are generated in CI, boolean ops support convex shapes (union of
concave shapes uses the convex hull), picture/pattern fills and image
placeholders are not in v1, components are one instance per slide, layout
assistance is smart guides (no auto-layout collision avoidance yet).

## Milestones

- **M0** scaffold + green CI
- **M1** installable APK from GitHub Releases — done (v0.1.0 → v0.2.1;
  releases are release-signed from v0.2.1)
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
