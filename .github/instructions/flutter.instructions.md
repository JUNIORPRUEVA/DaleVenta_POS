---
description: "Use when editing Flutter or Dart code in apps/fulltech_app (screens, widgets, Riverpod providers, models, routing, printing, tests). Covers the real Flutter commands, state/architecture rules, design-system reuse, and offline/cache constraints of this app."
applyTo: "apps/fulltech_app/**"
---

# Flutter client rules (`apps/fulltech_app`)

Stack: Flutter 3.41.6 / Dart 3.11.4 (`environment.sdk: ^3.10.1`), Riverpod 2, go_router 10, dio 5, flutter_secure_storage, shared_preferences, freezed / json_serializable. App version lives in `pubspec.yaml` (`1.0.5+124`).

Layout: `lib/core`, `lib/features`, `lib/modules`; widget/unit tests in `test/`; integration tests in `integration_test/`.

## Architecture

- Keep UI → state → data separation. Business logic does not belong in widgets.
- Riverpod is the single shared state source. Do not keep isolated per-screen copies of backend data, and do not "fix" a state problem with a forced UI refresh.
- Data comes from the API. Never hardcode dynamic values, company data, or catalog data in the client.
- Models: keep freezed / json_serializable usage consistent with neighbouring models. Changing a JSON key or field type requires checking the backend contract and existing cached/persisted local data (old clients and cached payloads must keep parsing).

## UI

- Read `docs/DESIGN_SYSTEM.md` before touching screens, widgets, navigation, layout, typography, colors, spacing, icons, dialogs, or empty/loading/error states.
- Reuse existing shared widgets and theme tokens. No arbitrary padding, radius, color, or font sizes.
- Check overflow/truncation, touch target size, contrast, responsive behavior, real text length, and all loading/error/empty states.
- User-facing strings stay in the app's existing Spanish tone.

## Commands (run from `apps/fulltech_app`)

- Dependencies: `flutter pub get`
- Static analysis: `flutter analyze`
- Tests: `flutter test` (all) or `flutter test test/modules/cotizaciones` / `flutter test test/<path>_test.dart`
- Integration tests: `flutter test integration_test/<file>.dart`
- Builds: `flutter build web --release`, `flutter build apk --release`, `flutter build windows --release`
- Windows release installers must be produced with `scripts/release/build_windows_release.ps1`, never with a raw `flutter build`.

## Gotchas verified in this environment

- `tester.binding.setSurfaceSize(...)` is effectively a no-op here; test width-based layouts with `tester.view.physicalSize` + `tester.view.devicePixelRatio` (and `addTearDown(tester.view.reset)`).
- Do not delete `.dart_tool` or run `flutter clean` unless a build corruption has been proven; those are diagnostic actions, not routine steps.
- Never point the app at production data for validation. Prefer local/dev targets; see `docs/ENVIRONMENTS.md`.
