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
    required TypingActivityDetector typingActivityDetector,
    required Future<AppStateSnapshot> Function() onShowPrompt,
    required Future<AppStateSnapshot> Function() onPromptTimedOut,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _clock = clock,
       _timerFactory = timerFactory,
       _typingActivityDetector = typingActivityDetector,
       _onShowPrompt = onShowPrompt,
       _onPromptTimedOut = onPromptTimedOut,
       _onError = onError;

  final Clock _clock;
  final SchedulerTimerFactory _timerFactory;
  final TypingActivityDetector _typingActivityDetector;
  final Future<AppStateSnapshot> Function() _onShowPrompt;
  final Future<AppStateSnapshot> Function() _onPromptTimedOut;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  SchedulerTimer? _reminderTimer;
  SchedulerTimer? _timeoutTimer;
  AppStateSnapshot? _snapshot;
  bool _disposed = false;

  void update(AppStateSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _snapshot = snapshot;
    _cancelTimers();
    _scheduleFrom(snapshot);
  }

  void dispose() {
    _disposed = true;
    _snapshot = null;
    _cancelTimers();
  }

  void _scheduleFrom(AppStateSnapshot snapshot) {
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
          () => unawaited(_handleReminderDue()),
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
          () => unawaited(_handlePromptTimedOut()),
        );
      case PromptStatus.expired:
        return;
    }
  }

  Future<void> _handleReminderDue() async {
    _reminderTimer = null;
    final snapshot = _snapshot;
    if (_disposed || snapshot == null || snapshot.activeTask == null) {
      return;
    }
    if (snapshot.runtimeState.promptState.isPending) {
      update(snapshot);
      return;
    }

    try {
      final deferral = await _typingDeferral(snapshot);
      if (_disposed) {
        return;
      }
      if (deferral != null) {
        _reminderTimer = _timerFactory.schedule(
          deferral,
          () => unawaited(_handleReminderDue()),
        );
        return;
      }

      update(await _onShowPrompt());
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }

  Future<void> _handlePromptTimedOut() async {
    _timeoutTimer = null;
    if (_disposed) {
      return;
    }

    try {
      update(await _onPromptTimedOut());
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }

  Future<Duration?> _typingDeferral(AppStateSnapshot snapshot) async {
    if (!snapshot.capabilities.supportsTypingActivity ||
        snapshot.settings.typingDeferralSeconds <= 0) {
      return null;
    }

    final lastTypingAt = await _typingActivityDetector.lastTypingActivityUtc();
    if (lastTypingAt == null) {
      return null;
    }

    final idleAt = lastTypingAt.toUtc().add(
      Duration(seconds: snapshot.settings.typingDeferralSeconds),
    );
    final now = _clock.nowUtc();
    if (!idleAt.isAfter(now)) {
      return null;
    }

    return idleAt.difference(now);
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
