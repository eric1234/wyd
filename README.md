# wyd

> [!WARNING]
> This app and codebase were generated largely with AI. It works well enough for the creator's personal use, but it may contain bugs, rough edges, and poor-quality code; do not treat it as an example of good software design or best practices.

`wyd` stands for "Whatcha ya doin?" It is a tray-based desktop time tracker
built with Flutter and Dart that stays out of the way in the system tray and
periodically asks the user to confirm or correct the current task.

## History

`wyd` is the spiritual successor to [`wd`](https://github.com/eric1234/wd), an
Electron-based version of the same idea that built about a decade earlier. This
implementation moves the app to Flutter because Electron proved too bulky and
awkward for a small utility that is meant to live quietly in the system tray.

## Development

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for local setup, useful commands,
testing workflows, and contribution guidelines.

## Development Snapshots

The [latest snapshot](https://github.com/eric1234/wyd/releases/tag/snapshot)
provides unsigned development builds from `main` for Linux x64, macOS Apple
Silicon, and Windows x64. These are complete Flutter desktop bundles rather
than installers; extract the entire ZIP before running the app.

Snapshots may be less stable than formal releases and operating systems may
warn about their unsigned binaries. The About window identifies snapshot
builds with version `0.0.0`, a build number, and the source commit. Linux users
should also review the platform dependency notes below.

## Platform Support Notes

Platforms:

- [x] Linux, with Ubuntu, Mint, Fedora, openSUSE and Xubuntu
- [x] macOS
- [x] Windows

Linux limitations:

- Hovering over the tray icon does not show the current task.
- Clicking tray icon launches menu as secondary click not supported.

### Fedora

On Fedora, run the following to enable tray support. First install the software:

```bash
sudo dnf install libayatana-appindicator-gtk3 gnome-shell-extension-appindicator
```

Next, log out and back in to make that software available to your desktop.
Finally enable the extension.

```bash
gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
```

### openSUSE

Because openSUSE is a KDE-based distro it likely does not have the
libayatana-appindicator package this application uses to register the tray
interaction. To install run:

```bash
sudo zypper install libayatana-appindicator3-1
```

### Xubuntu

Xubuntu does not install the library used for idle detection by default. The
app will still work but idle detection will be disabled. To enable it install
the necessary library:

```bash
sudo apt install libxcb-screensaver0
```

## License

This project is released into the public domain under the Unlicense. The
codebase is expected to be largely AI-written, and any copyrightable
contributions are dedicated to the public domain accordingly.

The software is provided "as is", without warranty or liability. See `UNLICENSE`
for the full text.
