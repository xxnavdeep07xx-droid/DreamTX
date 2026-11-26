# DreamTX — Project Plan (permanent)

This file is the single living plan for the project. Update it in the same PR that
completes an item. The checklists at the bottom are the source of truth for status.

---

## 1. What we are making

**DreamTX** — a presentation app (Flutter Android app + Rust engine + Cloudflare Worker).
The user's own AI (ChatGPT, Claude, Gemini, any MCP client) builds decks through MCP.
The app is the editor, presenter, and exporter (.pptx / .pdf).

Core pieces:
- `app/` — Flutter Android editor, presenter, Files drawer, Insert/Draw/Design tabs.
- `core/` — Rust engine (deck model, layout, DNAs, exporters). Native FFI + wasm.
- `worker/` — Cloudflare Worker: MCP endpoint, pairing Registry DO, per-deck Deck DO.
- `.github/workflows/` — CI: cargo tests, worker typecheck + MCP e2e, flutter analyze +
  widget tests, per-ABI release-signed APKs on tags.

## 2. Working rules (standing)

- **Branch:** `arena/937c19a3-dreamtx` only. Push only there; PRs only from there.
- **One feature PR in flight at a time.** Each increment is PR-sized and CI-green before merge.
- **CI is the only test oracle** (no local Flutter/Cargo). Keep static sweeps tight before pushing.
- **Each merged increment:** update this file, comment the step on issue #11, and tag/release
  when the milestone asks for an APK.
- **No core changes** unless the item says so (Wave 3 is the exception).
- **Build, don't cut**: gaps are built (fast, scoped), not deleted.
- **Timeline:** frontend completion in 2–5 days; backend (MCP / Worker deploy) after.
  Project freeze **Dec 2 2026** (token expiry); launch **Dec 3 2026**.

## 3. Roadmap (mirrors issue #11)

### Wave 1 — Insert Tier 1 (done except 6–7)
- [x] 1. Object actions (PR #12)
- [x] 2. Filmstrip sections (PR #13)
- [x] 3. WordArt (PR #14)
- [x] 4. Table depth (PR #15/#16)
- [x] 5. Image depth (PR #17, v0.2.40)
- [x] 6. Slide furniture (slide number / date / footer) — PR #32 (decision: rendered objects; exported through the text path, no exporter changes)
- [x] 7. Outline view (View tab) — PR #31 (merged): every slide with title + body preview; tap to jump, pencil renames the title. Body text editing stays in the slide itself (not in the outline yet).

### Wave 2 — Draw v2 (the current focus)
See section 4 for the full PowerPoint Draw-tab map.
- [x] A-1. Eraser sizes S/M/L + "Erase all ink on slide" (one undo step) — PR #22
- [x] A-2. Pen presets (saved tool chips, cap 6) + pencil tip style — PR #23
- [x] B. Lasso select — PR #24 (loop selects; move, recolor, delete as one undo step each; selection is editor-owned, not an engine group)
- [x] R. Ruler — PR #25 (editor-only tick rulers on the top and left edges; toggled from the Draw row; never exported)
- [x] D. Ink → shape, locally (line / rect / ellipse / triangle; deterministic heuristics; arrow not built) — PR #26
- [x] E. Ink replay (strokes animate in draw order; Draw-row button; display only, never exported) — PR #27
- [ ] C. Floating island (dock, 500 ms hold to lift, compact mode, persisted position, coach mark)
  - [x] C-1 (PR #28, merged): the Draw toolbox is a floating island over the canvas, docked top/bottom, 500 ms hold on the grip lifts it (haptic + shadow), drag follows the finger, release snaps to the nearer edge, dock saved per device (`island.json`). Pure rules in `core/island_math.dart`, tests in `test/island_test.dart`.
  - [x] C-2 (PR #29, merged): compact mode — a narrow column (Pen, Highlighter, Eraser, Lasso, colour dot) that docks to any corner; the colour dot opens the palette in a bottom sheet (the popover); toggles with the full toolbar's compact button and the column's expand button. Keep-outs: the island stays in the canvas area, so it never covers the ribbon or filmstrip.
  - [x] C-3 (PR #30, merged): one-time coach mark beside the island ("Hold the grip to move this toolbar", Got it); retired by dismissal or the first lift; saved in island.json.

### Wave 3 — Insert Tier 2 (core/protocol changes)
- [x] 1. Link / tap-action (`link {kind: url|slide, target}`; PPTX hyperlinks + PDF link annotations). Core PR #33, UI PR #34 (object actions → Link)
  - [x] 1a. Link badge on linked objects in edit mode (never while presenting)
  - [x] 1b. Presenter taps follow links: `url` opens outside the app (http, https, mailto only), `slide` jumps to that slide. A link tap does not also turn the page
- [x] 2. Chart (object kind, renderer, panel, both exporters). Native PPTX chart (chosen). Core PR #36, app PR #37. Known limits: literal data (no Edit Data in PowerPoint)
  - [x] 2a. Uncolored series take colors from the deck's DNA chart palette (`resolve_dna` → `chart_palette`; core and app share it)
  - [x] 2b. The chart sheet edits every series' values (one column per series); names and colors are kept

### Wave 4 — AI / Worker
- [~] Ink → text / math: DROPPED (user decision). The MCP server is the core product, so handwriting recognition is out of scope.
- [~] LIVE present (Registry DO + Deck DO + WebSocket broadcast): ON HOLD pending a decision after market feedback. Worker code exists in the repo but is not deployed (no Cloudflare account yet).

### Non-goals (unchanged unless the user says otherwise)
3D models, screen recording, compare/merge UI, B&W view.
Note: the **ruler** was a non-goal in the earlier design; it is now in scope (R) per the
Draw-tab request.

## 4. Draw tab — PowerPoint feature map

Status is checked against the code on `ad4b7d9` (before Draw A-1).

| # | PowerPoint Draw-tab feature | App status | Plan |
|---|---|---|---|
| 1 | Pen (ink) | **Exists** — pen tool, arms via tap | — |
| 2 | Highlighter | **Exists** — translucent 28px marker, exports translucent | — |
| 3 | Pen / ink color | **Exists** — palette band, DNA accent default | — |
| 4 | Pen thickness | **Exists** — S/M/L (4 / 8 / 16 px) | — |
| 5 | Eraser (stroke erase) | **Exists** — sweeps scribbles only; content immune | — |
| 6 | Eraser size | **Done** (A-1, PR #22) | — |
| 7 | Erase all ink on slide | **Done** (A-1, PR #22) | — |
| 8 | Pen presets / pen gallery | **Done** (A-2, PR #23) — session-scoped, cap 6, long-press removes | — |
| 9 | Pencil / pen tip styles | **Done** (A-2, PR #23) — thin translucent pen tip (no texture: the model has no grain) | — |
| 10 | Lasso select | **Done** (B, PR #24) — frame-center rule; move / recolor / delete as one batch | — |
| 11 | Ruler | **Done** (R, PR #25) — editor-only overlay | — |
| 12 | Ink replay | **Done** (E, PR #27) — replay button on the Draw row; scribbles draw in z-order; shapes from ink are not replayed | — |
| 13 | Ink to shape | **Done** (D, PR #26) — line, rect, ellipse, triangle; arrow not built | Arrow left as a follow-up |
| 14 | Ink to text | Missing — needs handwriting recognition | Dropped (user decision: MCP is the core) |
| 15 | Ink to math | Missing — needs math recognition | Dropped (user decision: MCP is the core) |
| 16 | Draw with touch (touch draws instead of selects) | **Covered** — Draw is an armed mode; the canvas consumes touches while armed; tap the tool again to disarm | — |

Extra (not PowerPoint, from the Draw v2 plan): **C. Floating island** (see Wave 2).

## 4b. Design tab — PowerPoint feature map

Status is checked against the code on `main` (`e3a1cf2`). The Design row holds the theme chips and the variant shuffle. The Files drawer holds slide size, and the View row holds slide furniture.

| # | PowerPoint Design-tab feature | App status | Plan |
|---|---|---|---|
| 1 | Themes gallery | **Done** — 5 families as chips (Swiss editorial, Cinematic, Magazine serif, Bold, Pastel). Each sets palette, fonts, corner and motif. Family changes apply to the whole deck; a slide's own background override is kept (row 11) | — |
| 2 | Variants gallery (colour variants) | **Done** — the shuffle button is replaced by a strip of 6 variants of the current family. Each shows its palette (background and accent); tap one to pick it. Core ops `dna_variants` and `set_dna_variant`; seeds limited to 53 bits so they survive the app's JSON | — |
| 3 | Theme colours (pick or edit) | **Missing** — palette comes from the DNA. The user cannot choose or edit it | Decide: palette picker over the DNA set |
| 4 | Theme fonts (pick) | **Missing** — fonts are fixed by the family (serif or sans roles) | Decide: font-pair picker |
| 5 | Slide size (16:9, 16:10, 4:3, 1:1) | **Exists**, but in the Files drawer (Aspect sheet), not Design | Surface it from Design, or leave and link |
| 6 | Custom slide size | **Missing** — presets only (`ASPECTS`) | Low priority |
| 7 | Format Background (solid, gradient, picture; apply to all) | **Partial — solid slice done** (PR #43, merged): solid colour per slide from the deck palette, "Default bg", and "Apply to all". Text switches to a readable ink on a custom background. Gradient and picture not built | Gradient and picture: follow-up PRs |
| 8 | Hide background graphics | **Done** (this PR) — per-slide `hide_graphics` flag in the core; the DNA motif is skipped on that slide, and exports and the presenter follow it. Design row chip: "Hide graphics". MCP tool not added yet | — |
| 9 | Design Ideas / Designer | **Not planned** — needs AI layout generation; the MCP server is the AI path | Out of scope for now |
| 10 | Slide furniture (slide number, date, footer) | **Exists** (Wave 1 item 6, PR #32), in the View row | — |
| 11 | Apply theme to selected slides only | **Decided: whole deck, with per-slide override** — a family applies to the whole deck; a slide's background (row 7) is an override and survives the change. Test `family_change_keeps_a_slide_background_override` | — |
| 12 | Motif choice | **Missing** — motif is set by the DNA, not picked | Decide with row 3 |

Proposed order (for the user to confirm): 8 (hide background graphics), then 7 (format background, the core change), then 2 (variant strip), then 1 and 11 (theme scope), then 3, 4, 12 (customisation), then 5 and 6 (size).

## 5. Known issues / risks

- **Issue writes via the sandbox:** resolved 2026-11-25 — the Arena app installation was
  granted Issues + Pull requests write. If comments/edits start returning 403 again, check
  github.com/settings/installations for a pending "Permission updates requested".
- **No local Flutter:** every UI change is verified only by CI. Keep changes small and
  pure-function-tested where possible (`ink_math.dart`).
- **Widget tests are brittle around gestures** (`warnIfMissed` on long-press; use explicit
  finders). See `TESTING.md`.
- **CI logs unreachable from the sandbox:** use `gh pr checks`, the signed-out Annotations
  page, and the `::error::` lines emitted by ci.yml.
- **Android platform folders are generated in CI** (not committed).
- **Ink to text/math** cannot be done offline in Dart with reasonable quality; it waits for
  the AI/Worker path. Do not fake it.
- **Exports:** highlighter opacity exports; eraser and lasso are editor-only (no export impact).
  Ruler is an overlay and never exports.
- **Presenter:** new Draw features that alter objects (ink→shape, lasso groups) must render
  identically in presenter mode.

## 6. Checklist (live status)

Last updated: 2026-11-25 (Draw E in PR #27).

- [x] Permanent plan file created (this file)
- [x] Draw-tab feature map written (section 4)
- [x] A-1 Eraser sizes + Erase all ink (PR #22)
- [x] A-2 Pen presets + pencil tip (PR #23)
- [x] B Lasso select (PR #24)
- [x] R Ruler (PR #25)
- [x] D Ink → shape (PR #26)
- [x] E Ink replay (PR #27)
- [x] C Floating island (PR #28 C-1, PR #29 C-2, PR #30 C-3)
- [x] Wave 1 items 6–7 (PR #31 outline, PR #32 furniture)
- [x] Wave 3 item 1 (link)
- [x] Wave 3 item 2 (chart, native PPTX)
- [x] Design tab feature map (section 4b)
- [ ] Wave 4 (ink→text/math, LIVE present)
