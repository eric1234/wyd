# wyd

`wyd` stands for "What's ya doin?" It is a tray-based desktop time tracker built with Flutter and Dart that stays out of the way in the system tray and periodically asks the user to confirm or correct the current task.

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
