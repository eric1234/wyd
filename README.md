# wyd

`wyd` stands for "What's ya doin?" It is a tray-based desktop time tracker
built with Flutter and Dart that stays out of the way in the system tray and
periodically asks the user to confirm or correct the current task.

## History

`wyd` is the spiritual successor to [`wd`](https://github.com/eric1234/wd), an
Electron-based version of the same idea that built about a decade earlier. This
implementation moves the app to Flutter because Electron proved too bulky and
awkward for a small utility that is meant to live quietly in the system tray.

## Getting Started

1. Install the Flutter SDK from the official Flutter installation guide for
   your platform.

2. Verify Flutter and enable desktop support for the platform you are
   developing on:

   ```bash
   flutter doctor
   flutter config --enable-linux-desktop
   flutter config --enable-macos-desktop
   ```

3. On Debian/Ubuntu Linux development machines, install the desktop build
   dependencies used by Flutter, the tray plugin, and idle detection:

   ```bash
   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
     libayatana-appindicator3-dev libxcb1-dev libxcb-screensaver0-dev \
     libwayland-dev lld-18
   ```

4. Install project dependencies:

   ```bash
   flutter pub get
   ```

5. Run the app in development:

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

## Useful Commands

```bash
flutter analyze
dart format .
flutter test
```

## Integration Tests

Run integration tests through the project script instead of invoking the
`integration_test` directory directly:

```bash
./tool/run_integration_tests.sh linux
./tool/run_integration_tests.sh macos
```

The script accepts a Flutter device ID as its first argument and runs each
`integration_test/*_test.dart` file in a separate Flutter process.

This per-file runner is the standard project workflow for all platforms. It
avoids a Flutter desktop integration-test harness issue where
`flutter test integration_test -d linux` can pass the first file and then fail a
later app launch with `Error waiting for a debug connection`.

## Platform Support Notes

`wyd` is currently aimed at Linux and macOS. Windows support is not available
yet and has not been tested.

Known platform differences:

- Linux has been tested on Mint (X11/Cinnamon) and Ubuntu (Wayland/Gnome).
  Others may or may not work but testing on those is coming.
- On Linux, hovering over the tray icon does not show the current task. Tray
  tooltips currently work on macOS only.
- On Linux, clicking the tray icon opens the menu. macOS has separate click
  behavior: primary click opens quick entry, and secondary click opens the
  menu.
- On macOS, locking the screen or putting the computer to sleep stops the active
  task automatically. Linux does not handle lock or sleep events yet.

## License

This project is released into the public domain under the Unlicense. The
codebase is expected to be largely AI-written, and any copyrightable
contributions are dedicated to the public domain accordingly.

The software is provided "as is", without warranty or liability. See `UNLICENSE`
for the full text.
