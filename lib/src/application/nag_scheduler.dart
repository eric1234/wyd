import 'dart:async';

import '../domain/domain.dart';
import 'app_state_snapshot.dart';
import 'clock.dart';
import 'platform_adapters.dart';

abstract interface class SchedulerTimer {
  bool get isActive;

  void cancel();
}

abstract interface class SchedulerTimerFactory {
  SchedulerTimer schedule(Duration duration, void Function() callback);
}

final class DartSchedulerTimerFactory implements SchedulerTimerFactory {
  const DartSchedulerTimerFactory();

  @override
  SchedulerTimer schedule(Duration duration, void Function() callback) {
    return _DartSchedulerTimer(Timer(_normalizeDuration(duration), callback));
  }
}

final class NagScheduler {
  NagScheduler({
    required Clock clock,
    required SchedulerTimerFactory timerFactory,
    required UserIdleDetector userIdleDetector,
    required Future<AppStateSnapshot> Function() onShowPrompt,
    required Future<AppStateSnapshot> Function() onPromptTimedOut,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _clock = clock,
       _timerFactory = timerFactory,
       _userIdleDetector = userIdleDetector,
       _onShowPrompt = onShowPrompt,
       _onPromptTimedOut = onPromptTimedOut,
       _onError = onError;

  final Clock _clock;
  final SchedulerTimerFactory _timerFactory;
  final UserIdleDetector _userIdleDetector;
  final Future<AppStateSnapshot> Function() _onShowPrompt;
  final Future<AppStateSnapshot> Function() _onPromptTimedOut;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  SchedulerTimer? _reminderTimer;
  SchedulerTimer? _timeoutTimer;
  AppStateSnapshot? _snapshot;
  int _generation = 0;
  bool _disposed = false;

  void update(AppStateSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _generation += 1;
    final generation = _generation;
    _snapshot = snapshot;
    _cancelTimers();
    _scheduleFrom(snapshot, generation);
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _snapshot = null;
    _cancelTimers();
  }

  void _scheduleFrom(AppStateSnapshot snapshot, int generation) {
    final activeTask = snapshot.activeTask;
    if (activeTask == null) {
      return;
    }

    switch (snapshot.runtimeState.promptState.status) {
      case PromptStatus.none:
        final anchor =
            snapshot.runtimeState.lastConfirmationAtUtc ??
            activeTask.startedAtUtc;
        _reminderTimer = _timerFactory.schedule(
          _durationUntil(
            anchor.add(_minutes(snapshot.settings.reminderIntervalMinutes)),
          ),
          () => unawaited(_handleReminderDue(generation)),
        );
      case PromptStatus.visible:
        final shownAt = snapshot.runtimeState.promptState.shownAtUtc;
        if (shownAt == null) {
          return;
        }
        _timeoutTimer = _timerFactory.schedule(
          _durationUntil(
            shownAt.add(_minutes(snapshot.settings.responseTimeoutMinutes)),
          ),
          () => unawaited(_handlePromptTimedOut(generation)),
        );
      case PromptStatus.expired:
        return;
    }
  }

  Future<void> _handleReminderDue(int generation) async {
    _reminderTimer = null;
    final snapshot = _snapshot;
    if (!_isCurrent(generation) ||
        snapshot == null ||
        snapshot.activeTask == null) {
      return;
    }
    if (snapshot.runtimeState.promptState.isPending) {
      update(snapshot);
      return;
    }

    try {
      final deferral = await _activityDeferral(snapshot);
      if (!_isCurrent(generation)) {
        return;
      }
      if (deferral != null) {
        _reminderTimer = _timerFactory.schedule(
          deferral,
          () => unawaited(_handleReminderDue(generation)),
        );
        return;
      }

      final promptSnapshot = await _onShowPrompt();
      if (!_isCurrent(generation)) {
        return;
      }
      update(promptSnapshot);
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }

  Future<void> _handlePromptTimedOut(int generation) async {
    _timeoutTimer = null;
    if (!_isCurrent(generation)) {
      return;
    }

    try {
      final snapshot = await _onPromptTimedOut();
      if (!_isCurrent(generation)) {
        return;
      }
      update(snapshot);
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }

  Future<Duration?> _activityDeferral(AppStateSnapshot snapshot) async {
    if (!snapshot.capabilities.supportsUserIdleDetection ||
        snapshot.settings.typingDeferralSeconds <= 0) {
      return null;
    }

    try {
      final deferral = await _userIdleDetector.promptDeferralFor(
        Duration(seconds: snapshot.settings.typingDeferralSeconds),
      );
      if (deferral == null || deferral <= Duration.zero) {
        return null;
      }
      return deferral;
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      return null;
    }
  }

  Duration _durationUntil(DateTime dueAtUtc) {
    return _normalizeDuration(dueAtUtc.toUtc().difference(_clock.nowUtc()));
  }

  void _cancelTimers() {
    _reminderTimer?.cancel();
    _timeoutTimer?.cancel();
    _reminderTimer = null;
    _timeoutTimer = null;
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _generation;
  }

  static Duration _minutes(int value) => Duration(minutes: value);
}

final class _DartSchedulerTimer implements SchedulerTimer {
  _DartSchedulerTimer(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() {
    _timer.cancel();
  }
}

Duration _normalizeDuration(Duration duration) {
  return duration.isNegative ? Duration.zero : duration;
}
