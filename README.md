# wyd

`wyd` stands for "What's ya doin?" It is a tray-based desktop time tracker built with Flutter and Dart that stays out of the way in the system tray and periodically asks the user to confirm or correct the current task.

## License

This project is released into the public domain under the Unlicense. The codebase is expected to be largely AI-written, and any copyrightable contributions are dedicated to the public domain accordingly.

The software is provided "as is", without warranty or liability. See `UNLICENSE` for the full text.

## Getting Started

1. Install the Flutter SDK and make sure desktop Linux support is enabled:

```bash
flutter doctor
flutter config --enable-linux-desktop
```

2. Install project dependencies:

```bash
flutter pub get
```

3. Run the app in development:

```bash
flutter run -d linux
```

4. Build a release binary:

```bash
flutter build linux --release
```

The built Linux app will be placed under `build/linux/`.

## Useful Commands

```bash
flutter test
flutter analyze
dart format .
```

See `PROJECT_SPEC.md` for the product and implementation spec.
