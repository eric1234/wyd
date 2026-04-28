import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('XdgAutostartStartupAtLoginAdapter', () {
    test('writes an XDG autostart desktop entry when enabled', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_autostart_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        appName: 'wyd test',
        executablePath: '/opt/wyd test/wyd',
        configHome: tempDirectory.path,
      );

      await adapter.setEnabled(true);

      final desktopFile = File(
        p.join(tempDirectory.path, 'autostart', 'dev.wyd.test.desktop'),
      );
      final content = await desktopFile.readAsString();
      expect(await adapter.isEnabled(), isTrue);
      expect(content, contains('Type=Application'));
      expect(content, contains('Name=wyd test'));
      expect(content, contains('Exec="/opt/wyd test/wyd"'));
      expect(content, contains('X-GNOME-Autostart-enabled=true'));
    });

    test('removes the desktop entry when disabled', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_autostart_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        executablePath: '/opt/wyd/wyd',
        configHome: tempDirectory.path,
      );

      await adapter.setEnabled(true);
      await adapter.setEnabled(false);

      expect(await adapter.isEnabled(), isFalse);
      expect(
        await File(
          p.join(tempDirectory.path, 'autostart', 'dev.wyd.test.desktop'),
        ).exists(),
        isFalse,
      );
    });

    test('treats hidden desktop entry as disabled', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_autostart_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final autostartDirectory = Directory(
        p.join(tempDirectory.path, 'autostart'),
      );
      await autostartDirectory.create(recursive: true);
      await File(
        p.join(autostartDirectory.path, 'dev.wyd.test.desktop'),
      ).writeAsString('''[Desktop Entry]
Type=Application
Hidden=true
''');
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        executablePath: '/opt/wyd/wyd',
        configHome: tempDirectory.path,
      );

      expect(await adapter.isEnabled(), isFalse);
    });

    test('uses XDG_CONFIG_HOME before HOME fallback', () async {
      final xdgDirectory = await Directory.systemTemp.createTemp(
        'wyd_xdg_config_',
      );
      final homeDirectory = await Directory.systemTemp.createTemp('wyd_home_');
      addTearDown(() => xdgDirectory.delete(recursive: true));
      addTearDown(() => homeDirectory.delete(recursive: true));
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        executablePath: '/opt/wyd/wyd',
        environment: {
          'XDG_CONFIG_HOME': xdgDirectory.path,
          'HOME': homeDirectory.path,
        },
      );

      await adapter.setEnabled(true);

      expect(
        await File(
          p.join(xdgDirectory.path, 'autostart', 'dev.wyd.test.desktop'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(
            homeDirectory.path,
            '.config',
            'autostart',
            'dev.wyd.test.desktop',
          ),
        ).exists(),
        isFalse,
      );
    });

    test('falls back to HOME .config when XDG_CONFIG_HOME is absent', () async {
      final homeDirectory = await Directory.systemTemp.createTemp('wyd_home_');
      addTearDown(() => homeDirectory.delete(recursive: true));
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        executablePath: '/opt/wyd/wyd',
        environment: {'HOME': homeDirectory.path},
      );

      await adapter.setEnabled(true);

      expect(
        await File(
          p.join(
            homeDirectory.path,
            '.config',
            'autostart',
            'dev.wyd.test.desktop',
          ),
        ).exists(),
        isTrue,
      );
    });

    test('requires HOME when no config home is available', () {
      expect(
        () => XdgAutostartStartupAtLoginAdapter(environment: const {}),
        throwsStateError,
      );
    });

    test('rejects unsafe desktop ids', () {
      expect(
        () => XdgAutostartStartupAtLoginAdapter(appId: '../wyd'),
        throwsArgumentError,
      );
      expect(
        () => XdgAutostartStartupAtLoginAdapter(appId: 'dev/wyd'),
        throwsArgumentError,
      );
    });

    test('treats GNOME disabled desktop entry as disabled', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_autostart_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final autostartDirectory = Directory(
        p.join(tempDirectory.path, 'autostart'),
      );
      await autostartDirectory.create(recursive: true);
      await File(
        p.join(autostartDirectory.path, 'dev.wyd.test.desktop'),
      ).writeAsString('''[Desktop Entry]
Type=Application
X-GNOME-Autostart-enabled=false
''');
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        executablePath: '/opt/wyd/wyd',
        configHome: tempDirectory.path,
      );

      expect(await adapter.isEnabled(), isFalse);
    });

    test('escapes desktop entry values and quoted exec paths', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_autostart_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final adapter = XdgAutostartStartupAtLoginAdapter(
        appId: 'dev.wyd.test',
        appName: 'wyd\\name\nnext',
        appComment: 'comment\\line\nnext',
        executablePath: '/opt/"wyd"\\app',
        configHome: tempDirectory.path,
      );

      await adapter.setEnabled(true);

      final content = await File(
        p.join(tempDirectory.path, 'autostart', 'dev.wyd.test.desktop'),
      ).readAsString();
      expect(content, contains('Name=wyd\\\\name\\nnext'));
      expect(content, contains('Comment=comment\\\\line\\nnext'));
      expect(content, contains('Exec="/opt/\\"wyd\\"\\\\app"'));
    });
  });
}
