# DreamTX

A premium presentation creation studio — starting with the Android app, built with Flutter.

## Status

Milestone 2: the **project creation experience** on top of the Dashboard + app shell.

- Creation options — start from scratch, import a file, or create with an external AI
  assistant (MCP-powered workflow).
- Project configuration — name, slide size (16:9 / 4:3 / 9:16 / custom in–cm), stored as
  real EMU dimensions in the project document.
- Import preview — native Android file picker, extension validation (PPTX / PDF / DOCX),
  honest "Import pending" staging for the future conversion engine.
- Local persistence — one JSON `.dreamtx` document per project in the app's private
  storage; nothing is faked when a save fails.
- AI & MCP connections screen introducing the external-assistant workflow (clearly marked
  demo state until the server ships).

The presentation editor, document conversion, the MCP server itself and the Rust/C++ core
are planned as separate development tasks and are intentionally not faked in this build.

## Design identity

- Deep charcoal surfaces with hairline borders — flat and restrained.
- The DreamTX mark: a neon-gradient chat bubble (violet → blue → sky → pink → orange → gold)
  with a play glyph, text bars and a sparkle burst — redesigned in SVG
  (`assets/brand/dreamtx_mark.svg`, plus a compact variant for tiny sizes) and reused as the
  adaptive/round/monochrome launcher icon and cold-start splash.
- Electric violet primary and periwinkle blue secondary, sampled from the mark; the gradient
  family appears only on brand moments (welcome headline, create action).
- Refined Roboto type scale with tight display letter-spacing.
- No glassmorphism; gradients stay confined to the brand moments.

## Screens

- **Dashboard** — welcome, primary "New Presentation" action, quick actions (import, blank
  project, design studio, open project), recent projects (rename / duplicate / delete with
  confirmation), design discovery, AI & MCP connections.
- **Creation options** — "Let's create something." Blank canvas, file import, or an AI
  assistant.
- **Project configuration** — presentation name (fallback "Untitled Presentation") and
  slide size with live dimension preview; the create action stays reachable above the
  keyboard.
- **Import preview** — file facts (name, extension, size, type), validation status and
  cancel / continue actions; unsupported formats get a tailored explanation.
- **Editor placeholder** — honest "editor is next" destination showing the persisted
  project facts (slide size, source, status).
- **AI & MCP connections** — how the external-assistant workflow works plus current
  (demo) connection state.
- **Explore / Library / Settings** — design direction discovery, all projects with
  overflow actions, preferences.

## Project structure

```
lib/
  app/              app widget, shell, routes, theme tokens
  features/
    connections/    AI & MCP connections screen
    dashboard/      dashboard screen + section widgets
    explore/        design direction discovery
    library/        project library
    projects/
      models/         PresentationProject, SlideSize (EMU-based)
      screens/        creation options, configuration, import preview, editor placeholder
      widgets/        option cards, slide size selector, name field, import file card
      services/       ProjectService, FileImportService
      repositories/   ProjectRepository + LocalProjectRepository (JSON documents)
  shared/
    models/          design collection, connection
    repositories/    mock implementations behind interfaces
    services/        service locator, native file picker, app storage
    widgets/         reusable UI (logo, cards, thumbnails, painters)
    utils/           formatting helpers
```

Storage lives behind `ProjectRepository`; screens never touch file IO, so the JSON store
can be swapped for a database or the future native core without UI changes.

## Building locally

```bash
flutter pub get
flutter run                 # on a device / emulator
flutter build apk --release
```

## CI

Every push to `main` runs analyze + tests, builds a release APK and attaches it to a
GitHub Release (workflow: `.github/workflows/android-apk.yml`).

## Test signing note

`android/app/dreamtx-test.keystore` and `android/key.properties` are committed on purpose:
they hold a **development-only test key** so CI can produce installable APKs for testing.
Replace them with your own keystore before publishing to any store.

## Roadmap

- Presentation editor & rendering engine
- Document import engine (PDF / DOCX / PPTX conversion)
- Design engine (dynamic compositions, not templates)
- MCP server & AI assistant connections
- Rust/C++ native core
