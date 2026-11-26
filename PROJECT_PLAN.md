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
- [ ] 1. Link / tap-action (`link {kind: url|slide, target}`; PPTX hyperlinks + PDF link annotations)
- [ ] 2. Chart (object kind, renderer, panel, both exporters; decision: native PPTX chart vs grouped shapes)

### Wave 4 — AI / Worker
- [ ] Ink → text / math (through the AI tab; needs recognition — AI/Worker dependent)
- [ ] LIVE present (Worker deploy: Registry DO + Deck DO + WebSocket broadcast)

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
| 14 | Ink to text | Missing — needs handwriting recognition | **Wave 4** (AI/Worker) |
| 15 | Ink to math | Missing — needs math recognition | **Wave 4** (AI/Worker) |
| 16 | Draw with touch (touch draws instead of selects) | **Covered** — Draw is an armed mode; the canvas consumes touches while armed; tap the tool again to disarm | — |

Extra (not PowerPoint, from the Draw v2 plan): **C. Floating island** (see Wave 2).

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
- [ ] Wave 3 items 1–2
- [ ] Wave 4 (ink→text/math, LIVE present)
