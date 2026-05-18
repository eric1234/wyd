import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('LaunchAtStartupStartupAtLoginAdapter', () {
    test('configures the launch_at_startup package on creation', () {
      late ({String appName, String appPath, String? packageName}) setupCall;

      LaunchAtStartupStartupAtLoginAdapter(
        appName: 'wyd test',
        appPath: '/Applications/wyd.app',
        packageName: 'dev.wyd.test',
        setup:
            ({
              required String appName,
              required String appPath,
              String? packageName,
            }) {
              setupCall = (
                appName: appName,
                appPath: appPath,
                packageName: packageName,
              );
            },
        enable: () async {},
        disable: () async {},
        isEnabled: () async => false,
      );

      expect(setupCall.appName, 'wyd test');
      expect(setupCall.appPath, '/Applications/wyd.app');
      expect(setupCall.packageName, 'dev.wyd.test');
    });

    test('delegates enable, disable, and status checks', () async {
      var enabled = false;
      final adapter = LaunchAtStartupStartupAtLoginAdapter(
        appPath: '/Applications/wyd.app',
        setup:
            ({
              required String appName,
              required String appPath,
              String? packageName,
            }) {},
        enable: () async => enabled = true,
        disable: () async => enabled = false,
        isEnabled: () async => enabled,
      );

      expect(await adapter.isEnabled(), isFalse);

      await adapter.setEnabled(true);
      expect(await adapter.isEnabled(), isTrue);

      await adapter.setEnabled(false);
      expect(await adapter.isEnabled(), isFalse);
    });

    test('rejects unsafe setup values', () {
      expect(
        () => LaunchAtStartupStartupAtLoginAdapter(
          appName: '',
          appPath: '/Applications/wyd.app',
          setup: _noopSetup,
        ),
        throwsArgumentError,
      );
      expect(
        () => LaunchAtStartupStartupAtLoginAdapter(
          appPath: 'bad\npath',
          setup: _noopSetup,
        ),
        throwsArgumentError,
      );
      expect(
        () => LaunchAtStartupStartupAtLoginAdapter(
          appPath: '/Applications/wyd.app',
          packageName: 'bad\rpackage',
          setup: _noopSetup,
        ),
        throwsArgumentError,
      );
    });
  });
}

void _noopSetup({
  required String appName,
  required String appPath,
  String? packageName,
}) {}
