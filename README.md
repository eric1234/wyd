# wyd

`wyd` stands for "What's ya doin?" It is a tray-based desktop time tracker built with Flutter and Dart that stays out of the way in the system tray and periodically asks the user to confirm or correct the current task.

## Getting Started

1. Install the Flutter SDK from the official Flutter installation guide for your platform.

2. Verify Flutter and enable desktop support for the platform you are developing on:

```bash
flutter doctor
flutter config --enable-linux-desktop
```

macOS and Windows runners are present from Flutter's project template, but the product currently gates the tray app to Linux while those platforms wait for later tray-first lifecycle work.

3. On Debian/Ubuntu Linux development machines, install the desktop build dependencies used by Flutter, the tray plugin, and SQLite native assets:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-dev libayatana-appindicator3-dev lld-18
```

4. Install project dependencies:

```bash
flutter pub get
```

5. Run the app in development:

```bash
flutter run -d linux
```

6. Build a release binary:

```bash
flutter build linux --release
```

The built Linux app will be placed under `build/linux/`.

## Useful Commands

```bash
flutter analyze
dart format .
flutter test
```

## Integration Tests

Run integration tests through the project script instead of invoking the `integration_test` directory directly:

```bash
./tool/run_integration_tests.sh linux
```

The script accepts a Flutter device ID and runs each `integration_test/*_test.dart` file in a separate Flutter process. Linux is the supported v1 target:

```bash
WYD_INTEGRATION_DEVICE=linux ./tool/run_integration_tests.sh
```

This per-file runner is the standard project workflow for all platforms. It avoids a Flutter desktop integration-test harness issue where `flutter test integration_test -d linux` can pass the first file and then fail a later app launch with `Error waiting for a debug connection`.

## Platform Capabilities

Linux currently supports the required tray workflow, local SQLite persistence, hidden startup, single-instance activation routing, quick entry, nag timeout, reports, settings, recovery, and XDG autostart-based start-at-login.

The current Linux implementation uses the primary Flutter window for quick entry and separate warmed child windows for report/settings. The child windows are preloaded hidden so first visible use is responsive, then report/settings data is refreshed when the warmed window is actually shown.

The following optional capabilities are intentionally disabled unless a reliable platform adapter is added for the target session:

- Lock/sleep detection: unsupported by default; the app exposes the adapter seam and tests simulated events.
- Recent typing detection: unsupported by default, so typing deferral is disabled in settings and nags show normally.
- Tray-relative popup positioning: unsupported by default; popup windows are centered through `window_manager`.

Linux integration tests use fake platform adapters for workflows that are unreliable in headless or sessionless CI. Real tray behavior still requires a manual smoke pass on the target desktop session.

See `PROJECT_SPEC.md` for the product and implementation spec.

## License

This project is released into the public domain under the Unlicense. The codebase is expected to be largely AI-written, and any copyrightable contributions are dedicated to the public domain accordingly.

The software is provided "as is", without warranty or liability. See `UNLICENSE` for the full text.
