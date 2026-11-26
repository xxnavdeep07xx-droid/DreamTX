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
                        layout solver, .pptx/.pdf export, FFI + wasm entry;
                        font metrics as a generated advance table (no TTFs)
app/                    Flutter app (Android). Run `flutter create .` once
                        (see app/README) — platform folders are CI-generated.
worker/                 Cloudflare Worker: MCP endpoint, pairing Registry DO,
                        per-deck Deck DO (state, version log, WS hibernation)
scripts/                Local dev helpers (build android .so, typecheck
                        worker, regenerate the font advance table)
.github/workflows       CI: core tests (native+wasm), worker typecheck + MCP
                        flow against real workerd, flutter analyze + widget
                        suite, per-ABI release-signed APK on tags
```

## Design philosophy (the moat)

The AI never places pixels. It speaks **semantics** (archetypes: stat wall,
split, comparison, chart hero...); the Rust engine owns layout, type scale,
and color. Three curated deck DNAs ship in v1 — **Swiss editorial** (default),
**cinematic**, **magazine serif** — each with seeded per-deck variation, plus a
pacing governor (no same archetype twice in a row, density rhythm, whitespace
budget) so decks never look template-stamped.

## What's in the app (v0.2.38)

**Look** — dark studio theme (black chrome, charcoal surfaces, red accents,
one purple→pink→orange signature gradient on create actions and the live
slide's filmstrip ring).

**Decks home** — editorial deck grid; New deck button in the masthead;
long-press a deck card for open / rename / delete; immersive full-screen
mode (system bars hidden, edge-swipe to reveal).

**Editor** — canvas + filmstrip; a PowerPoint-style ribbon (AI · Files ·
Insert · Draw · Design · Transitions · Animations · Slide show · Review ·
View · Help); add / duplicate / reorder / delete slides (long-press a
thumbnail); full per-slide content forms for all 9 archetypes (cover, agenda,
section, statement, stat wall, split, comparison, chart hero, closing);
design family (DNA) switcher; undo/redo (60 steps, safe mid-typing); deck
rename; comments.

**Insert drawer** — rides the ribbon's top edge like Files: a 3×2 grid
(Text Box, Image, Shapes, Table, Icons / Stickers, Media); inserting or
tapping an object swaps the grid for that object's editing panel. Text boxes
edit WYSIWYG on the canvas — a horizontally scrollable toolbar rides above
the keyboard while typing; with the keyboard closed, the full panel carries
Quick Tools / Character / Paragraph & Box.

**Draw toolbox** — the ribbon's contextual band: pen (the deck's DNA
accent by default, S/M/L widths) and a translucent highlighter (28dp
marker, 35% opacity — which the PPTX and PDF exporters already honor, so
ink exports translucent too). Strokes are smoothed at capture time
(Douglas-Peucker + quadratic-midpoint resampling, a 400-point budget)
and land as first-class path objects — movable, restylable, z-ordered,
1:1 in exports, MCP-visible. The stroke eraser sweeps scribbles only
(text boxes, images, shapes are immune by signature), dims its targets
live, and commits the whole sweep as one undo step. Eraser sizes S/M/L
(reach 12 / 24 / 40 px), and "Erase all ink on this slide" clears every
scribble on the slide in one undo step. A lasso (drag a loop) selects every object it encloses, which then move, recolor, or delete together, one undo step each. A pencil tip (thin, slightly
translucent pen) sits beside the pen, and saved presets (up to 6, per
session) hold a tool's color and width as one-tap chips.

**Files drawer & resources** — Open · Browse over Android SAF (folder import
through the host channel); per-deck resource libraries for images and media;
deleting an object / slide / deck sweeps unreferenced assets (respecting the
undo stack).

**Objects on canvas** — text boxes, images, icons, media, tables and vector
shapes in one true Z-order (Bring Forward / Send Backward reads on screen and
in exports); selectable / draggable in every editing tab; media objects
resolve their file and play through the system player.

**Design mode** (editor toolbar) — 36 preset shapes + the Draw toolbox's ink;
move / resize / rotate handles with 15-degree snap and smart guides (snap to
slide edges, centers, other objects); fills: solid, linear + radial gradient;
stroke: width, dash styles, start/end arrowheads; effects: shadow, glow,
opacity; boolean ops (union / subtract / intersect — convex shapes); group /
ungroup, lock, 6-way align, layers panel (reorder / lock / delete);
components: save a selection as a reusable component, place it on any slide,
update it globally. Objects export 1:1 into PPTX and PDF.

**Presenter** — the editor's own stage (the shared SlideStage render) at the
deck's own aspect ratio, never a hardcoded one.

**Export** — .pptx and .pdf via the share sheet, rendered on a background
isolate (the UI never freezes): real object content in both — styled text
runs, tables, icon cards, images embedded as real assets (PPTX media parts /
PDF XObjects), media as its card — with per-slide Z-order honored.

**AI via MCP** — pairing sheet ready; goes live when the Worker deploys (M2).

Release APKs are release-signed (keystore stored as GitHub Actions secrets)
and split per ABI (arm64-v8a / armeabi-v7a / x86_64 — each device downloads
only its own slice, ~60-65% smaller). Installs from releases before v0.2.1
were debug-signed — uninstall those before installing v0.2.1+ (Android
refuses updates across signers).

## State (M1 done)

- Rust core: real model, 3 DNAs + variation, pacing, layout solver, pptx +
  pdf exporters with real object content, JSON command protocol, FFI + wasm
  exports; font metrics as a pre-generated ~130 KB advance table (DejaVu TTFs
  and ttf-parser dropped — same widths, slimmer binaries); smoke tests.
- Worker: full MCP (initialize/tools list/call) over Streamable HTTP + SSE,
  pairing Registry DO (code+secret, TTL, attempt limiting), Deck DO with
  hibernating WebSocket broadcast and version log. Not yet deployed.
- Flutter: everything under "What's in the app" above; the widget suite
  (138 tests at v0.2.40 — image depth added 7) keeps the contracts.
- CI: cargo test (native + wasm32), worker typecheck + end-to-end MCP flow
  against a local workerd, flutter analyze + widget tests, resolved-pin and
  lock-drift gates, per-ABI release-signed APK on tags.

## Known v0.2 limits

- PDF export is Latin-first (base-14 fonts, non-Latin is transliterated; full
  font embedding/subsetting lands with CJK metrics in M2).
- CJK glyph widths are approximated (the advance table is DejaVu-derived).
- Android platform folders are generated in CI, not committed.
- Boolean ops support convex shapes (union of concave shapes uses the convex
  hull).
- Picture/pattern fills and image placeholders are not in v1.
- Highlighter strokes darken where they overlap (each stroke is its own
  object; a single composited ink plane is a v2 hook).
- Components are one instance per slide.
- Media objects export as their card (video/audio bytes are not embedded in
  PPTX/PDF).
- Layout assistance is smart guides (no auto-layout collision avoidance yet).

## Milestones

- **M0** scaffold + green CI
- **M1** installable APK from GitHub Releases — done (v0.1.0 → v0.2.38;
  release-signed since v0.2.1, per-ABI since v0.2.36)
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

The layout solver's font metrics ship as a generated advance table —
`core/crates/deck-core/src/font_metrics.rs`, produced from the repo root by
`scripts/gen_font_table.py` from the DejaVu faces (Bitstream Vera / Public
Domain license terms). No TTFs are embedded at build time — see
`core/crates/deck-core/fonts/README.md`.
