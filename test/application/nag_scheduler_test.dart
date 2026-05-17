import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('NagScheduler', () {
    test('does not schedule while idle', () {
      final harness = _Harness();

      harness.scheduler.update(harness.snapshot(activeTask: null));

      expect(harness.timers.activeTimers, isEmpty);
    });

    test('schedules reminder from last confirmation while tracking', () {
      final harness = _Harness();
      final lastConfirmationAt = DateTime.utc(2026, 1, 1, 9);
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 5);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 8)),
          runtimeState: RuntimeState(lastConfirmationAtUtc: lastConfirmationAt),
        ),
      );

      expect(
        harness.timers.activeTimers.single.duration,
        const Duration(minutes: 10),
      );
    });

    test(
      'shows prompt when reminder becomes due and schedules timeout',
      () async {
        final harness = _Harness();
        final shownAt = DateTime.utc(2026, 1, 1, 9, 15);
        harness.clock.current = shownAt;
        harness.onShowPrompt = () async {
          return harness.snapshot(
            activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
            runtimeState: RuntimeState(
              promptState: PromptState.visible(shownAt),
            ),
          );
        };

        harness.scheduler.update(
          harness.snapshot(
            activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
            runtimeState: RuntimeState(
              lastConfirmationAtUtc: DateTime.utc(2026, 1, 1, 9),
            ),
          ),
        );
        await harness.timers.fireFirst();

        expect(harness.showPromptCalls, 1);
        expect(
          harness.timers.activeTimers.single.duration,
          const Duration(minutes: 1),
        );
      },
    );

    test('defers due reminder when idle detector requests deferral', () async {
      final harness = _Harness(
        userIdleDetector: _FakeUserIdleDetector(
          deferrals: [const Duration(seconds: 5)],
        ),
      );
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          capabilities: const PlatformCapabilities(
            supportsUserIdleDetection: true,
          ),
        ),
      );
      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 0);
      expect(
        harness.timers.activeTimers.single.duration,
        const Duration(seconds: 5),
      );
    });

    test('shows due reminder when idle detector permits prompt', () async {
      final userIdleDetector = _FakeUserIdleDetector(deferrals: [null]);
      final harness = _Harness(userIdleDetector: userIdleDetector);
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          capabilities: const PlatformCapabilities(
            supportsUserIdleDetection: true,
          ),
        ),
      );
      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 1);
      expect(userIdleDetector.minimumIdleDurations, [
        const Duration(seconds: 5),
      ]);
    });

    test(
      'does not defer reminder when idle detection capability is unsupported',
      () async {
        final userIdleDetector = _FakeUserIdleDetector(
          deferrals: [const Duration(seconds: 5)],
        );
        final harness = _Harness(userIdleDetector: userIdleDetector);
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

        harness.scheduler.update(
          harness.snapshot(
            activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          ),
        );
        await harness.timers.fireFirst();

        expect(harness.showPromptCalls, 1);
        expect(userIdleDetector.minimumIdleDurations, isEmpty);
      },
    );

    test(
      'timeout callback transitions expired prompt to idle scheduling',
      () async {
        final harness = _Harness();
        final shownAt = DateTime.utc(2026, 1, 1, 9, 15);
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 16);
        harness.onPromptTimedOut = () async {
          return harness.snapshot(
            activeTask: null,
            runtimeState: RuntimeState(
              promptState: PromptState.expired(shownAt),
            ),
          );
        };

        harness.scheduler.update(
          harness.snapshot(
            activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
            runtimeState: RuntimeState(
              promptState: PromptState.visible(shownAt),
            ),
          ),
        );
        await harness.timers.fireFirst();

        expect(harness.timeoutCalls, 1);
        expect(harness.timers.activeTimers, isEmpty);
      },
    );

    test('updating to idle cancels an existing reminder', () {
      final harness = _Harness();
      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
        ),
      );

      harness.scheduler.update(harness.snapshot(activeTask: null));

      expect(harness.timers.timers.single.isActive, isFalse);
      expect(harness.timers.activeTimers, isEmpty);
    });

    test('schedules overdue reminder immediately', () {
      final harness = _Harness();
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 16);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          runtimeState: RuntimeState(
            lastConfirmationAtUtc: DateTime.utc(2026, 1, 1, 9),
          ),
        ),
      );

      expect(harness.timers.activeTimers.single.duration, Duration.zero);
    });

    test('schedules overdue timeout immediately', () {
      final harness = _Harness();
      final shownAt = DateTime.utc(2026, 1, 1, 9, 15);
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 17);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          runtimeState: RuntimeState(promptState: PromptState.visible(shownAt)),
        ),
      );

      expect(harness.timers.activeTimers.single.duration, Duration.zero);
    });

    test('activity deferral setting of zero disables deferral', () async {
      final userIdleDetector = _FakeUserIdleDetector(
        deferrals: [const Duration(seconds: 5)],
      );
      final harness = _Harness(userIdleDetector: userIdleDetector);
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          settings: const AppSettings(typingDeferralSeconds: 0),
          capabilities: const PlatformCapabilities(
            supportsUserIdleDetection: true,
          ),
        ),
      );
      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 1);
      expect(userIdleDetector.minimumIdleDurations, isEmpty);
    });

    test('re-checks after deferral while activity continues', () async {
      final harness = _Harness(
        userIdleDetector: _FakeUserIdleDetector(
          deferrals: [
            const Duration(seconds: 5),
            const Duration(seconds: 2),
            null,
          ],
        ),
      );
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          capabilities: const PlatformCapabilities(
            supportsUserIdleDetection: true,
          ),
        ),
      );
      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 0);
      expect(
        harness.timers.activeTimers.single.duration,
        const Duration(seconds: 5),
      );

      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 0);
      expect(
        harness.timers.activeTimers.single.duration,
        const Duration(seconds: 2),
      );

      await harness.timers.fireFirst();

      expect(harness.showPromptCalls, 1);
    });

    test('ignores obsolete reminder after idle check awaits', () async {
      final userIdleDetector = _DelayedUserIdleDetector();
      final harness = _Harness(userIdleDetector: userIdleDetector);
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          capabilities: const PlatformCapabilities(
            supportsUserIdleDetection: true,
          ),
        ),
      );
      final firing = harness.timers.fireFirst();
      await userIdleDetector.waitForRequest();

      harness.scheduler.update(harness.snapshot(activeTask: null));
      userIdleDetector.complete(const Duration(seconds: 5));
      await firing;
      await Future<void>.delayed(Duration.zero);

      expect(harness.showPromptCalls, 0);
      expect(harness.timers.activeTimers, isEmpty);
    });

    test('ignores obsolete prompt result after snapshot changes', () async {
      final harness = _Harness();
      final promptCompleter = Completer<AppStateSnapshot>();
      harness.onShowPrompt = () => promptCompleter.future;

      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
        ),
      );
      final firing = harness.timers.fireFirst();
      await Future<void>.delayed(Duration.zero);

      harness.scheduler.update(harness.snapshot(activeTask: null));
      promptCompleter.complete(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          runtimeState: RuntimeState(
            promptState: PromptState.visible(harness.clock.current),
          ),
        ),
      );
      await firing;
      await Future<void>.delayed(Duration.zero);

      expect(harness.showPromptCalls, 1);
      expect(harness.timers.activeTimers, isEmpty);
    });

    test('show prompt errors are reported and leave no active timer', () async {
      final harness = _Harness();
      harness.onShowPrompt = () async => throw StateError('show failed');
      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
        ),
      );

      await harness.timers.fireFirst();

      expect(harness.errors.single, isA<StateError>());
      expect(harness.timers.activeTimers, isEmpty);
    });

    test('timeout errors are reported and leave no active timer', () async {
      final harness = _Harness();
      harness.onPromptTimedOut = () async => throw StateError('timeout failed');
      harness.scheduler.update(
        harness.snapshot(
          activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
          runtimeState: RuntimeState(
            promptState: PromptState.visible(DateTime.utc(2026, 1, 1, 9, 15)),
          ),
        ),
      );

      await harness.timers.fireFirst();

      expect(harness.errors.single, isA<StateError>());
      expect(harness.timers.activeTimers, isEmpty);
    });
  });
}

final class _Harness {
  _Harness({UserIdleDetector? userIdleDetector})
    : clock = _FakeClock(DateTime.utc(2026, 1, 1, 9, 15)),
      timers = _FakeSchedulerTimerFactory() {
    scheduler = NagScheduler(
      clock: clock,
      timerFactory: timers,
      userIdleDetector: userIdleDetector ?? const UnsupportedUserIdleDetector(),
      onShowPrompt: () {
        showPromptCalls += 1;
        return onShowPrompt();
      },
      onPromptTimedOut: () {
        timeoutCalls += 1;
        return onPromptTimedOut();
      },
      onError: (error, stackTrace) {
        errors.add(error);
      },
    );
  }

  final _FakeClock clock;
  final _FakeSchedulerTimerFactory timers;
  late final NagScheduler scheduler;
  int showPromptCalls = 0;
  int timeoutCalls = 0;
  final List<Object> errors = [];
  late Future<AppStateSnapshot> Function() onShowPrompt = () async {
    return snapshot(
      activeTask: _activeTask(startedAtUtc: DateTime.utc(2026, 1, 1, 9)),
      runtimeState: RuntimeState(
        promptState: PromptState.visible(clock.current),
      ),
    );
  };
  late Future<AppStateSnapshot> Function() onPromptTimedOut = () async {
    return snapshot(activeTask: null);
  };

  AppStateSnapshot snapshot({
    required ActiveTask? activeTask,
    RuntimeState? runtimeState,
    AppSettings settings = AppSettings.defaults,
    PlatformCapabilities capabilities = const PlatformCapabilities(),
  }) {
    return AppStateSnapshot(
      activeTask: activeTask,
      runtimeState:
          runtimeState ?? RuntimeState(lastConfirmationAtUtc: clock.current),
      settings: settings,
      capabilities: capabilities,
    );
  }
}

ActiveTask _activeTask({required DateTime startedAtUtc}) {
  return ActiveTask(
    taskText: 'Write docs',
    taskTextNormalized: 'write docs',
    startedAtUtc: startedAtUtc,
    sourceEventId: 1,
  );
}

final class _FakeClock implements Clock {
  _FakeClock(this.current);

  DateTime current;

  @override
  DateTime nowUtc() => current;
}

final class _FakeUserIdleDetector implements UserIdleDetector {
  _FakeUserIdleDetector({required List<Duration?> deferrals})
    : _deferrals = List<Duration?>.of(deferrals);

  final List<Duration?> _deferrals;
  final List<Duration> minimumIdleDurations = [];

  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) async {
    minimumIdleDurations.add(minimumIdleDuration);
    if (_deferrals.isEmpty) {
      return null;
    }
    return _deferrals.removeAt(0);
  }
}

final class _DelayedUserIdleDetector implements UserIdleDetector {
  final Completer<void> _requestCompleter = Completer<void>();
  final Completer<Duration?> _resultCompleter = Completer<Duration?>();

  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) {
    if (!_requestCompleter.isCompleted) {
      _requestCompleter.complete();
    }
    return _resultCompleter.future;
  }

  Future<void> waitForRequest() => _requestCompleter.future;

  void complete(Duration? deferral) {
    _resultCompleter.complete(deferral);
  }
}

final class _FakeSchedulerTimerFactory implements SchedulerTimerFactory {
  final List<_FakeSchedulerTimer> timers = [];

  List<_FakeSchedulerTimer> get activeTimers {
    return timers.where((timer) => timer.isActive).toList();
  }

  @override
  SchedulerTimer schedule(Duration duration, void Function() callback) {
    final timer = _FakeSchedulerTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  Future<void> fireFirst() async {
    activeTimers.first.fire();
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeSchedulerTimer implements SchedulerTimer {
  _FakeSchedulerTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _callback();
  }
}
