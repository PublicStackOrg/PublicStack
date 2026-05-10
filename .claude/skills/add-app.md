---
name: add-app
description: Use when the user asks to add a Flutter frontend app to an existing Public Service — "add a new app", "add a kiosk app", "create a staff dashboard", "scaffold a new resident-facing UI", "add a Flutter frontend". Wraps `publicstack add app <name>`.
---

# add-app

Add a new Flutter app under an existing Public Service's `apps/`
directory. Wraps `publicstack add app`.

## When this fires

User says any of:

- "Add a new Flutter app called inspector"
- "Create a staff dashboard"
- "Add a kiosk app"
- "Scaffold a resident-facing frontend"

Do NOT use this skill for backend services (`add-internal-service`)
or shared Dart packages in `libraries/ui/` (those are hand-edited).

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up from CWD looking for
   `BLUEPRINT_VERSION`. If missing:
   - Surface: "You're not inside a Public Service."
   - Suggest: invoke `new-service` first, or `cd` into an existing PS.
   - HALT.

2. `publicstack` on PATH. Otherwise point at `~/publicstack/install.sh`.

3. (Warn, don't HALT.) `flutter` on PATH. If missing, the file
   generation still works but the dev loop step won't run locally —
   warn the user.

## Primary flow

1. **Gather inputs.** Ask via AskUserQuestion:
   - **App name** (Flutter package convention: lowercase + underscores
     only, regex `^[a-z][a-z0-9_]{1,49}$`). Reject hyphens — Flutter
     pubspec.yaml doesn't accept them.
   - **Purpose** (one-line description used in pubspec + lib/main.dart
     title). Common choices: "resident-facing UI" / "city staff
     dashboard" / "in-person terminal interface" / other.

2. **Run the CLI:**

   ```bash
   publicstack add app <slug>
   ```

   This:
   - Generates `apps/<slug>/` from the bundled app cookiecutter
     (pubspec.yaml, lib/main.dart, test/widget_test.dart, web/index.html,
     project.json for NX).
   - Edits root `package.json` to add `"flutter:<slug>":
     "./scripts/flutter-run.sh <slug>"` to the scripts table.

3. **Verify wiring:**

   ```bash
   cat apps/<slug>/pubspec.yaml | head -5         # name + description
   grep "flutter:<slug>" package.json             # npm script
   ```

4. **Suggest next steps:**

   ```bash
   cd apps/<slug>
   flutter pub get
   cd ../..
   npm run flutter:<slug>                # spins up flutter run -d chrome
   ```

   If `flutter` isn't on PATH, tell the user the file tree is ready;
   they'll need to install Flutter (https://flutter.dev/) to run it
   locally. The CI step in `template/.github/workflows/ci.yml` already
   builds + analyzes every app under `apps/`, so first-deploy
   verification still works.

## Branches

### User picks a name with hyphens (e.g., `staff-dashboard`)

Reject; pubspec.yaml requires underscores. Suggest `staff_dashboard`
or just `staff`.

### User wants a non-Flutter app (e.g., React, plain HTML)

The blueprint's app convention is Flutter — that's how `libraries/ui/`
(the shared design system + a11y helpers + EventBus pattern) is
consumed. A React app wouldn't get any of that for free.

Surface the tradeoff. If the user insists, document that the right
path is to NOT use this skill — they'd hand-create the React/HTML
project under `apps/<name>/` and skip the cookiecutter. They lose
`libraries/ui/` integration; they lose the Phase 5 accessibility
check (which scans Flutter web builds via Playwright + axe-core).
Phase 5 SPIKES.md #4 keeps this option open as a fallback.

### App name collides with existing app

`apps/<slug>/` already exists → CLI errors. Suggest a different name
or remove the existing directory first.

## Failure recovery

- **Partial generation.** If `publicstack add app` errored midway,
  `apps/<slug>/` may exist with no package.json wiring. Suggest
  `rm -rf apps/<slug>/` before retry.
- **`flutter pub get` fails.** Surface the verbatim error. Common
  causes: outdated Flutter SDK, dependency conflict in pubspec.yaml,
  network issues fetching pub.dev. Suggest `flutter upgrade` first.

## Worked example

User says: "Add a kiosk app called check_in."

1. Verify CWD is `Parking/` (or any v0.4.0 PS). `BLUEPRINT_VERSION`
   confirmed.

2. Verify `publicstack` ✓, `flutter` ✓.

3. AskUserQuestion:
   - name: `check_in` ✓ (lowercase + underscore, valid)
   - purpose: "In-person check-in terminal for city employees"

4. Run:

   ```bash
   publicstack add app check_in
   ```

5. CLI emits:

   ```
   ok: added apps/check_in
     next: cd apps/check_in && flutter pub get; then `npm run flutter:check_in`.
   ```

6. Verify wiring:

   ```bash
   $ head -2 apps/check_in/pubspec.yaml
   name: check_in
   description: "check_in app for this PublicStack Public Service."
   $ grep "flutter:check_in" package.json
       "flutter:check_in": "./scripts/flutter-run.sh check_in"
   ```

7. Run `cd apps/check_in && flutter pub get` and `cd ../.. && npm run
   flutter:check_in`. Flutter web build runs against `http://localhost:3003`
   or similar.

End state: working Flutter app shell at `apps/check_in/`, ready for
the user to fill in `lib/` with their UI.
