import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

import '../../application/application.dart';

typedef LaunchAtStartupSetup =
    void Function({
      required String appName,
      required String appPath,
      String? packageName,
    });

final class LaunchAtStartupStartupAtLoginAdapter
    implements StartupAtLoginAdapter {
  LaunchAtStartupStartupAtLoginAdapter({
    String appName = 'wyd',
    String? appPath,
    String? packageName = 'dev.wyd.tracker',
    LaunchAtStartupSetup? setup,
    Future<void> Function()? enable,
    Future<void> Function()? disable,
    Future<bool> Function()? isEnabled,
  }) : _enable = enable ?? _enableLaunchAtStartup,
       _disable = disable ?? _disableLaunchAtStartup,
       _isEnabled = isEnabled ?? launchAtStartup.isEnabled {
    (setup ?? _setupLaunchAtStartup)(
      appName: _validateValue(appName, 'appName'),
      appPath: _validateValue(
        appPath ?? Platform.resolvedExecutable,
        'appPath',
      ),
      packageName: packageName == null
          ? null
          : _validateValue(packageName, 'packageName'),
    );
  }

  final Future<void> Function() _enable;
  final Future<void> Function() _disable;
  final Future<bool> Function() _isEnabled;

  @override
  Future<bool> isEnabled() {
    return _isEnabled();
  }

  @override
  Future<void> setEnabled(bool enabled) {
    return enabled ? _enable() : _disable();
  }

  static String _validateValue(String value, String fieldName) {
    if (value.isEmpty || _containsControlCharacter(value)) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Launch-at-startup values must not be empty or contain control characters.',
      );
    }
    return value;
  }

  static bool _containsControlCharacter(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) {
        return true;
      }
    }
    return false;
  }

  static void _setupLaunchAtStartup({
    required String appName,
    required String appPath,
    String? packageName,
  }) {
    launchAtStartup.setup(
      appName: appName,
      appPath: appPath,
      packageName: packageName,
    );
  }

  static Future<void> _enableLaunchAtStartup() async {
    await launchAtStartup.enable();
  }

  static Future<void> _disableLaunchAtStartup() async {
    await launchAtStartup.disable();
  }
}
