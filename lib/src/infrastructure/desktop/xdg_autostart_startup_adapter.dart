import 'dart:io';

import 'package:path/path.dart' as p;

import '../../application/application.dart';

final class XdgAutostartStartupAtLoginAdapter implements StartupAtLoginAdapter {
  XdgAutostartStartupAtLoginAdapter({
    String appId = 'dev.wyd.tracker',
    String appName = 'wyd',
    String? appComment,
    String? executablePath,
    String? configHome,
    Map<String, String>? environment,
  }) : _appId = appId,
       _appName = appName,
       _appComment = appComment ?? "What's ya doin? tray-based time tracker",
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _configHome = configHome ?? _defaultConfigHome(environment);

  final String _appId;
  final String _appName;
  final String _appComment;
  final String _executablePath;
  final String _configHome;

  File get _desktopFile {
    return File(p.join(_configHome, 'autostart', '$_appId.desktop'));
  }

  @override
  Future<bool> isEnabled() async {
    final file = _desktopFile;
    if (!await file.exists()) {
      return false;
    }

    final content = await file.readAsString();
    return !content.contains(RegExp(r'^Hidden=true$', multiLine: true)) &&
        !content.contains(
          RegExp(r'^X-GNOME-Autostart-enabled=false$', multiLine: true),
        );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final file = _desktopFile;
    if (!enabled) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(_desktopEntryContent());
  }

  String _desktopEntryContent() {
    return '''[Desktop Entry]
Type=Application
Version=1.0
Name=${_escapeValue(_appName)}
Comment=${_escapeValue(_appComment)}
Exec=${_quoteExecPath(_executablePath)}
Terminal=false
X-GNOME-Autostart-enabled=true
''';
  }

  static String _defaultConfigHome(Map<String, String>? environment) {
    final env = environment ?? Platform.environment;
    final xdgConfigHome = env['XDG_CONFIG_HOME'];
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      return xdgConfigHome;
    }

    final home = env['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is required to configure XDG autostart.');
    }

    return p.join(home, '.config');
  }

  static String _escapeValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll('\n', r'\n');
  }

  static String _quoteExecPath(String path) {
    final escaped = path.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
