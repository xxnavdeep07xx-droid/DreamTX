# Testing DreamTX

Short notes for building test APKs, installing them, and collecting startup
evidence when something misbehaves on a phone. Companion to the release
process (tag push → CI → per-ABI APKs on the GitHub Release).

## Building a test APK (release mode)

Every APK is release-mode, built only by CI — there is no local
Flutter/Android SDK in this environment.

- **Without publishing a release** (preferred for test builds): on GitHub →
  Actions → **apk** workflow → *Run workflow* on `main` (workflow_dispatch).
  The build (~15 min) ends with two artifacts on the run page:
  - `dreamtx-apk` — the three per-ABI `app-*-release.apk` (arm64-v8a /
     armeabi-v7a / x86_64), release-signed exactly like a store build, plus
     `debug-info` for symbolicating release stack traces;
  - `pubspec-lock` — the exact resolved dependency lock used by the build
     (traceability: which plugin versions are actually inside the APK).
- **Full release**: bump `version:` in `app/pubspec.yaml` (build number must
  exceed the last distributed APK — currently **42**), commit, `git tag
  vX.Y.Z`, push the tag. CI verifies the resolved `path_provider_android`
  pin (must be `2.2.23`, the pre-JNI build), enforces the committed
  `app/pubspec.lock` byte-for-byte, runs `flutter analyze` + the widget smoke
  suite, builds the 3-ABI Rust core, and attaches the three per-ABI APKs to
  the tag's Release.

To download an artifact: run page → *Artifacts* → download zip → extract
the APKs. (Artifacts require a GitHub login; releases don't.)

## Installing on the phone

```bash
adb install -r app-arm64-v8a-release.apk   # in-place update, data kept
# curl fallback from the phone itself (pick your ABI):
# curl -LO https://github.com/xxnavdeep07xx-droid/DreamTX/releases/download/vX.Y.Z/app-arm64-v8a-release.apk
```

Sideloading **over the running app** is supported (writes are atomic and the
store opens through the method-channel build of path_provider) — but the
polite order is: force-stop DreamTX, install, reopen.

## Collecting startup evidence (Logcat)

Every storage step logs with the `[deck-store]` tag; the first launch after
an install is where all startup bugs show up:

```bash
adb logcat -c                  # clear
adb shell am force-stop com.dreamtx
adb shell monkey -p com.dreamtx -c android.intent.category.LAUNCHER 1
adb logcat -s flutter          # only the Dart prints: [deck-store], [pair-sheet]
```

What a healthy offline first launch looks like (order and counts may vary):
no `ClassNotFoundException`, no `DexPathList`, and at most
`load attempt 1/2 failed` followed by the deck list rendering. Any
`[deck-store] scan skipped N unreadable deck file(s): …` line names the
exact files that were unreadable — distinct from a genuinely empty library,
which logs nothing.

Quick on-device checks for the app-private deck directory (same dir since
the first release):

```bash
adb shell run-as com.dreamtx ls -la app_flutter/decks
```

## Local suites (host, no device)

- `app`: `flutter analyze && flutter test` — startup happy/empty/thrown/
  stalled + Retry recovery, save serialization (latest-snapshot-wins,
  failed-write-preserves-previous-file, delete-vs-pending-write), filmstrip
  geometry, pair-sheet offline behavior. Runs in CI before Gradle.
- `core`: `cargo test --all` (native) and the wasm32 build.
- `worker`: `npm run build:wasm && npx tsc --noEmit && node --test test/` —
  the full MCP pairing→mutation→app-update flow against a local
  `wrangler dev` Worker, with the Rust wasm engine asserted active
  (`/health` → `engine: "wasm"`).

## Acceptance checklist for an update on the affected phone

1. Clean install AND in-place update over the running app, same signing key.
2. Launch offline: home screen settles — deck list, empty state, or the
   error card with Retry; never a spinner loop, never an auto-close.
3. Create a deck, edit it, force-stop, reopen — deck persisted.
4. First-launch logcat captured if anything fails; check the resolved
   `path_provider_android` version in the run's `pubspec-lock` artifact.
