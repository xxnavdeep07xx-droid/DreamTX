# DreamTX

A premium presentation creation studio — starting with the Android dashboard, built with Flutter.

## Status

Foundation milestone: the Dashboard + app shell (Explore / Library / Settings), a mock data
layer behind repositories, and CI builds that produce installable release APKs.

The presentation editor, AI & MCP connection layer, document import and the Rust/C++ core are
planned as separate development tasks and are intentionally not faked in this build.

## Design identity

- Deep charcoal surfaces with hairline borders — flat and restrained.
- Muted violet as the primary accent, cool blue as the secondary accent.
- A custom geometric mark (two overlapping diamonds — layered slides).
- Refined Roboto type scale with tight display letter-spacing.
- No heavy gradients, no neon, no glassmorphism.

## Screens

- **Dashboard** — welcome, primary "New Presentation" action, quick actions (import, blank
  project, design studio, open project), recent projects (rename / duplicate / delete with
  confirmation), design discovery, AI & MCP connections (clearly marked demo state).
- **Explore** — searchable design directions.
- **Library** — all projects with overflow actions.
- **Settings** — appearance, workspace preferences, licenses.
- **Placeholder flows** — new presentation, file import (real Android file picker via a
  platform channel), notifications.

## Project structure

```
lib/
  app/            app widget, shell, routes, theme tokens
  features/
    dashboard/    dashboard screen + section widgets
    explore/      design direction discovery
    library/      project library
    settings/     preferences
    projects/     new presentation & import flows
  shared/
    models/       project, design collection, connection
    repositories/ mock implementations behind interfaces
    services/     service locator, native file picker
    widgets/      reusable UI (logo, cards, thumbnails, painters)
    utils/        formatting helpers
```

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
- Document import (PDF / DOCX / PPTX)
- Design engine (dynamic compositions, not templates)
- AI & MCP connection layer
- Rust/C++ native core
