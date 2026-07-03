# Agent Notes

## Project Snapshot
- `wyd` is a Flutter/Dart desktop tray time tracker for Linux, macOS, and Windows.
- It lives in the system tray/menu bar, periodically asks the user to confirm or correct the current task, and stores data locally in SQLite.
- Keep the product small: this is a local-first tray utility, not a full time-tracking platform.

## Code Map
- `lib/main.dart`: boots the resident tray app and child report/settings windows.
- `lib/src/domain/`: pure task text, activity log, timeline/report, lifecycle, runtime state, and settings logic. Keep Flutter and platform APIs out.
- `lib/src/application/`: orchestration services, scheduling, single-writer coordination, tray menu/window coordination, and adapter interfaces.
- `lib/src/infrastructure/`: SQLite repositories and desktop platform adapters for tray, windows, single-instance, power/lifecycle, and startup behavior.
- `lib/src/ui/`: Flutter controllers and views for quick entry, reports, settings, and top-level app widgets.
- `test/` mirrors unit/widget coverage; `integration_test/` covers desktop workflow and persistence smoke tests.

## Useful Commands
- `flutter pub get`
- `dart format .`
- `flutter analyze`
- `flutter test`
- `./tool/run_integration_tests.sh linux`
- `./tool/run_integration_tests.sh macos`
- `./tool/run_integration_tests.sh windows`

Run integration tests through `tool/run_integration_tests.sh`, not by targeting the whole `integration_test` directory. The script runs each file in a separate Flutter process to avoid desktop debug-connection issues.

## Working Guidelines
- Prefer the smallest correct change and follow existing layer boundaries.
- Keep domain behavior platform-independent and easy to unit test.
- Route platform-specific behavior through existing adapter interfaces and capability-aware fallbacks.
- Preserve append-only activity-log semantics for task history; use existing services/repositories for persisted state changes.
- Add or update targeted tests for behavior changes; real tray behavior may still require a manual desktop smoke test.
- Keep user-facing docs concise.
