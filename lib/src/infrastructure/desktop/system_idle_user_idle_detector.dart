import 'dart:async';

import 'package:system_idle/system_idle.dart';
import 'package:system_idle_platform_interface/system_idle_platform_interface.dart';

import '../../application/application.dart';

typedef SystemIdlePluginFactory = SystemIdlePlatformInterface Function();

final class SystemIdleUserIdleDetector implements UserIdleDetector {
  SystemIdleUserIdleDetector._duration({
    required Future<Duration?> Function() getIdleDuration,
  }) : _getIdleDuration = getIdleDuration,
       _eventPlugin = null;

  SystemIdleUserIdleDetector._event({
    required SystemIdlePlatformInterface plugin,
  }) : _getIdleDuration = null,
       _eventPlugin = plugin;

  static const _eventModeRecheckDelay = Duration(seconds: 1);

  final Future<Duration?> Function()? _getIdleDuration;
  final SystemIdlePlatformInterface? _eventPlugin;
  Duration? _eventMinimumIdleDuration;
  StreamSubscription<bool>? _eventSubscription;
  bool? _eventIsIdle;
  bool _eventStreamFailed = false;

  static Future<SystemIdleUserIdleDetector?> create({
    SystemIdlePluginFactory? pluginFactory,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    try {
      final plugin = (pluginFactory ?? SystemIdle.forPlatform)();
      Future<void> disposeIgnoringErrors() async {
        try {
          await plugin.dispose();
        } catch (_) {}
      }

      try {
        await plugin.initialize();
        if (!plugin.isSupported) {
          logger.debug('system_idle detector unsupported');
          await disposeIgnoringErrors();
          return null;
        }

        final idleDuration = await plugin.getIdleDuration();
        if (idleDuration == null) {
          logger.debug('system_idle detector using event mode');
          return SystemIdleUserIdleDetector._event(plugin: plugin);
        }

        logger.debug('system_idle detector using duration mode');
        return SystemIdleUserIdleDetector._duration(
          getIdleDuration: plugin.getIdleDuration,
        );
      } catch (error, stackTrace) {
        logger.error(
          'system_idle detector initialization failed',
          error,
          stackTrace,
        );
        await disposeIgnoringErrors();
        return null;
      }
    } catch (error, stackTrace) {
      logger.error('system_idle detector creation failed', error, stackTrace);
      return null;
    }
  }

  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) async {
    if (minimumIdleDuration <= Duration.zero) {
      return null;
    }

    final getIdleDuration = _getIdleDuration;
    if (getIdleDuration != null) {
      return _durationModeDeferralFor(getIdleDuration, minimumIdleDuration);
    }

    return _eventModeDeferralFor(minimumIdleDuration);
  }

  Future<Duration?> _durationModeDeferralFor(
    Future<Duration?> Function() getIdleDuration,
    Duration minimumIdleDuration,
  ) async {
    try {
      final idleDuration = await getIdleDuration();
      if (idleDuration == null || idleDuration >= minimumIdleDuration) {
        return null;
      }

      return minimumIdleDuration - idleDuration;
    } catch (_) {
      return null;
    }
  }

  Future<Duration?> _eventModeDeferralFor(Duration minimumIdleDuration) async {
    try {
      await _ensureEventSubscription(minimumIdleDuration);
      if (_eventStreamFailed) {
        await _clearEventSubscription();
        return null;
      }
      if (_eventIsIdle == true) {
        return null;
      }

      return _eventRecheckDelayFor(minimumIdleDuration);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureEventSubscription(Duration minimumIdleDuration) async {
    if (_eventMinimumIdleDuration == minimumIdleDuration &&
        _eventSubscription != null) {
      return;
    }

    await _clearEventSubscription();

    final stream = _eventPlugin!.onIdleChanged(
      idleDuration: minimumIdleDuration,
    );
    _eventSubscription = stream.listen(
      (isIdle) {
        _eventIsIdle = isIdle;
      },
      onError: (_, _) {
        _eventStreamFailed = true;
      },
    );
    _eventMinimumIdleDuration = minimumIdleDuration;
  }

  Future<void> _clearEventSubscription() async {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    _eventMinimumIdleDuration = null;
    _eventIsIdle = null;
    _eventStreamFailed = false;
    await subscription?.cancel();
  }

  Duration _eventRecheckDelayFor(Duration minimumIdleDuration) {
    if (minimumIdleDuration < _eventModeRecheckDelay) {
      return minimumIdleDuration;
    }
    return _eventModeRecheckDelay;
  }
}
