import 'package:system_idle/system_idle.dart';

import '../../application/application.dart';

final class SystemIdleUserIdleDetector implements UserIdleDetector {
  const SystemIdleUserIdleDetector._({
    required Future<Duration?> Function() getIdleDuration,
  }) : _getIdleDuration = getIdleDuration;

  final Future<Duration?> Function() _getIdleDuration;

  static Future<SystemIdleUserIdleDetector?> create() async {
    try {
      final plugin = SystemIdle.forPlatform();
      Future<void> disposeIgnoringErrors() async {
        try {
          await plugin.dispose();
        } catch (_) {}
      }

      try {
        await plugin.initialize();
        if (!plugin.isSupported) {
          await disposeIgnoringErrors();
          return null;
        }

        final idleDuration = await plugin.getIdleDuration();
        if (idleDuration == null) {
          await disposeIgnoringErrors();
          return null;
        }

        return SystemIdleUserIdleDetector._(
          getIdleDuration: plugin.getIdleDuration,
        );
      } catch (_) {
        await disposeIgnoringErrors();
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) async {
    if (minimumIdleDuration <= Duration.zero) {
      return null;
    }

    try {
      final idleDuration = await _getIdleDuration();
      if (idleDuration == null || idleDuration >= minimumIdleDuration) {
        return null;
      }

      return minimumIdleDuration - idleDuration;
    } catch (_) {
      return null;
    }
  }
}
