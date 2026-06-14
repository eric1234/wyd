# Contributing to wyd

Thank you for contributing to `wyd`. This project is a small, local-first
Flutter desktop tray utility for Linux and macOS. Contributions should preserve
that focus: lightweight desktop time tracking, local SQLite persistence, and a
quiet tray/menu-bar experience.

## Ways to Contribute

- Report bugs with a clear description, platform, Flutter version, desktop
  environment, reproduction steps, expected behavior, and actual behavior.
- Propose small improvements that fit the tray utility scope.
- Fix bugs or add targeted behavior with tests when practical.
- Improve user-facing documentation when setup, platform behavior, or workflows
  are unclear.

For larger changes, open an issue or discussion before investing heavily. This
is especially important for platform support, data model changes, background
behavior, startup behavior, or anything that affects user privacy.

## Development Setup

1. Install the Flutter SDK for your platform.

2. Verify Flutter and enable desktop support:

   ```bash
   flutter doctor
   flutter config --enable-linux-desktop
   flutter config --enable-macos-desktop
   ```

3. On Debian/Ubuntu Linux machines, install the desktop dependencies used by
   Flutter, tray integration, and idle detection:

   ```bash
   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
     libayatana-appindicator3-dev libxcb1-dev libxcb-screensaver0-dev \
     libwayland-dev lld-18
   ```

4. Install project dependencies:

   ```bash
   flutter pub get
   ```

5. Run the app locally:

   ```bash
   flutter run -d linux
   flutter run -d macos
   ```

6. Build a release binary:

   ```bash
   flutter build linux --release
   flutter build macos --release
   ```

   The built apps will be placed under `build/linux/` and `build/macos/`.

## Project Structure

- `lib/main.dart` boots the resident tray app and child report/settings windows.
- `lib/src/domain/` contains pure business logic for task text, activity logs,
  reports, lifecycle state, runtime state, and settings.
- `lib/src/application/` coordinates scheduling, single-writer behavior, tray
  menu/window workflows, and adapter interfaces.
- `lib/src/infrastructure/` contains SQLite repositories and desktop platform
  adapters for tray, windows, single-instance behavior, power/lifecycle, and
  startup behavior.
- `lib/src/ui/` contains Flutter controllers and views for quick entry, reports,
  settings, and top-level app widgets.
- `test/` mirrors unit and widget coverage.
- `integration_test/` covers desktop workflow and persistence smoke tests.

Keep changes within the appropriate layer. Domain code should remain independent
of Flutter widgets and platform APIs. Platform-specific behavior should go
through adapter interfaces and capability-aware fallbacks.

## Coding Guidelines

- Prefer the smallest correct change over broad rewrites.
- Keep the product local-first. Do not add network services, telemetry, cloud
  sync, accounts, or background data export without prior agreement.
- Preserve append-only activity-log semantics for task history. Use existing
  services and repositories for persisted state changes.
- Follow the project's Flutter lint configuration and run `dart format .` before
  submitting code.
- Keep UI changes consistent with a tray/menu-bar utility: fast, unobtrusive,
  keyboard-friendly, and usable on desktop-sized and small windows.
- Avoid adding dependencies unless they are clearly necessary and well maintained.
- Do not commit generated build output, local databases, secrets, logs, or IDE
  state.

## Testing

Run the checks that match your change. For most code changes, run:

```bash
dart format .
flutter analyze
flutter test
```

Run integration tests through the project script, not by targeting the whole
`integration_test` directory directly:

```bash
./tool/run_integration_tests.sh linux
./tool/run_integration_tests.sh macos
```

The script runs each `integration_test/*_test.dart` file in a separate Flutter
process to avoid desktop debug-connection issues. Pass the Flutter device ID as
the first argument, such as `linux` or `macos`.

Add or update targeted tests for behavior changes. Platform tray behavior,
startup behavior, idle detection, and window-management changes may also need a
manual desktop smoke test on the affected platform.

### Testing GitHub Actions changes locally

When changing `.github/workflows/`, smoke-test the Linux CI matrix leg with
[`act`](https://github.com/nektos/act) when possible:

```bash
mkdir -p /tmp/act-artifacts
flutter clean
act pull_request -j ci --matrix platform:linux \
  --artifact-server-path /tmp/act-artifacts
```

The first time you run this it will ask what image to use. The "medium" one
is sufficient.

`act` is only a local Linux smoke test. It does not validate the hosted
`macos-latest` runner, so macOS CI changes still need to be verified by a real
GitHub Actions run. Avoid `act --reuse` when validating Linux apt/package
changes because previously installed packages can hide missing dependencies.

## Pull Request Checklist

Before opening a pull request, verify that:

- The change is focused and the PR description explains the motivation.
- Relevant tests were added or updated.
- `dart format .`, `flutter analyze`, and relevant tests pass, or any skipped
  checks are explained.
- User-facing behavior changes are reflected in documentation when appropriate.
- UI changes include screenshots or a short description of the desktop behavior.
- Linux and macOS behavior were considered. Windows runner files may exist from
  the Flutter template, but runtime support is currently limited to Linux and
  macOS.

## Bug Reports

Useful bug reports include:

- Operating system and version.
- Desktop environment or window manager on Linux.
- Flutter version from `flutter --version`.
- Steps to reproduce the issue from a clean launch when possible.
- Whether the issue affects tray interaction, prompts, reports, startup,
  persistence, or idle detection.
- Any relevant logs with private task names removed.

Do not share real task history, local database files, secrets, or other private
data in public reports.

## License and Contribution Terms

This project is released into the public domain under the Unlicense. By
contributing, you agree that any copyrightable contribution you submit is also
dedicated to the public domain under the same terms. See `UNLICENSE` for the full
license text.
