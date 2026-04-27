import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('TrackerService', () {
    test(
      'submitTask starts a task and updates runtime confirmation state',
      () async {
        final harness = _Harness();

        final snapshot = await harness.service.submitTask(' Write docs ');

        expect(snapshot.activeTask!.taskText, 'Write docs');
        expect(
          snapshot.runtimeState.lastConfirmationAtUtc,
          harness.clock.current,
        );
        expect(snapshot.runtimeState.cleanShutdown, isFalse);
        expect(harness.store.events.map((event) => event.eventType), [
          ActivityEventType.startTask,
        ]);
      },
    );

    test(
      'confirmation updates scheduler state without appending an event',
      () async {
        final harness = _Harness();
        await harness.service.submitTask('Write   Docs');
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 30);

        final snapshot = await harness.service.submitTask('write\tdocs');

        expect(snapshot.activeTask!.taskText, 'Write   Docs');
        expect(
          snapshot.runtimeState.lastConfirmationAtUtc,
          harness.clock.current,
        );
        expect(harness.store.events, hasLength(1));
      },
    );

    test('submitTask switches to a different task while active', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);

      final snapshot = await harness.service.submitTask('Fix bug');

      expect(snapshot.activeTask!.taskText, 'Fix bug');
      expect(harness.store.events.map((event) => event.eventType), [
        ActivityEventType.startTask,
        ActivityEventType.switchTask,
      ]);
    });

    test(
      'stopTask writes a manual stop only while active and clears prompt',
      () async {
        final harness = _Harness();
        await harness.service.submitTask('Write docs');
        await harness.service.nagPromptShown();
        harness.clock.current = DateTime.utc(2026, 1, 1, 10);

        final snapshot = await harness.service.stopTask();

        expect(snapshot.activeTask, isNull);
        expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
        expect(harness.store.events.last.eventType, ActivityEventType.stopTask);
        expect(harness.store.events.last.source, ActivitySource.manualStop);
      },
    );

    test(
      'nag timeout writes stop at prompt shown time and marks prompt expired',
      () async {
        final harness = _Harness();
        await harness.service.submitTask('Write docs');
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);
        await harness.service.nagPromptShown();
        final shownAt = harness.clock.current;
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 16);

        final snapshot = await harness.service.nagPromptTimedOut();

        expect(snapshot.activeTask, isNull);
        expect(snapshot.runtimeState.promptState.status, PromptStatus.expired);
        expect(harness.store.events.last.source, ActivitySource.nagTimeout);
        expect(harness.store.events.last.occurredAtUtc, shownAt);
        expect(harness.store.events.last.createdAtUtc, harness.clock.current);
      },
    );

    test('submit after timeout starts a fresh task', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      await harness.service.nagPromptShown();
      await harness.service.nagPromptTimedOut();
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);

      final snapshot = await harness.service.submitTask('Write docs');

      expect(snapshot.activeTask!.taskText, 'Write docs');
      expect(harness.store.events.map((event) => event.eventType), [
        ActivityEventType.startTask,
        ActivityEventType.stopTask,
        ActivityEventType.startTask,
      ]);
    });

    test('exit does not duplicate stop when prompt already expired', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      await harness.service.nagPromptShown();
      await harness.service.nagPromptTimedOut();

      final snapshot = await harness.service.exitRequested();

      expect(snapshot.runtimeState.cleanShutdown, isTrue);
      expect(
        harness.store.events.where(
          (event) => event.eventType == ActivityEventType.stopTask,
        ),
        hasLength(1),
      );
      expect(harness.store.events.last.source, ActivitySource.nagTimeout);
    });

    test('exit writes exit stop when a task is active', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);

      final snapshot = await harness.service.exitRequested();

      expect(snapshot.activeTask, isNull);
      expect(snapshot.runtimeState.cleanShutdown, isTrue);
      expect(harness.store.events.last.source, ActivitySource.exit);
      expect(harness.store.events.last.occurredAtUtc, harness.clock.current);
    });

    test('recoverOnStartup marks clean shutdown launches as running', () async {
      final harness = _Harness();
      harness.store.runtimeState = RuntimeState(cleanShutdown: true);

      final snapshot = await harness.service.recoverOnStartup();

      expect(snapshot.runtimeState.cleanShutdown, isFalse);
      expect(harness.store.events, isEmpty);
    });

    test('recovery uses pending prompt shown timestamp when active', () async {
      final harness = _Harness();
      harness.store.events.add(
        ActivityLogEvent.startTask(
          id: harness.store.nextId++,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      );
      final shownAt = DateTime.utc(2026, 1, 1, 9, 15);
      harness.store.runtimeState = RuntimeState(
        lastConfirmationAtUtc: DateTime.utc(2026, 1, 1, 9),
        promptState: PromptState.visible(shownAt),
        cleanShutdown: false,
      );

      final snapshot = await harness.service.recoverOnStartup();

      expect(snapshot.activeTask, isNull);
      expect(harness.store.events.last.source, ActivitySource.recovery);
      expect(harness.store.events.last.occurredAtUtc, shownAt);
      expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
    });

    test('recovery falls back to last confirmation timestamp', () async {
      final harness = _Harness();
      harness.store.events.add(
        ActivityLogEvent.startTask(
          id: harness.store.nextId++,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      );
      final lastConfirmationAt = DateTime.utc(2026, 1, 1, 9, 30);
      harness.store.runtimeState = RuntimeState(
        lastConfirmationAtUtc: lastConfirmationAt,
        cleanShutdown: false,
      );

      await harness.service.recoverOnStartup();

      expect(harness.store.events.last.source, ActivitySource.recovery);
      expect(harness.store.events.last.occurredAtUtc, lastConfirmationAt);
    });

    test('valid settings persist and invalid settings are rejected', () async {
      final harness = _Harness();

      expect(
        () => harness.service.updateSettings(
          const AppSettings(
            reminderIntervalMinutes: 1,
            responseTimeoutMinutes: 2,
          ),
        ),
        throwsA(isA<AppSettingsValidationException>()),
      );
      await harness.service.updateSettings(
        const AppSettings(
          reminderIntervalMinutes: 20,
          responseTimeoutMinutes: 5,
        ),
      );

      expect(harness.store.settings.reminderIntervalMinutes, 20);
      expect(harness.store.settings.responseTimeoutMinutes, 5);
    });

    test(
      'transaction failure rolls back partial mutations and surfaces error',
      () async {
        final harness = _Harness();
        harness.runner.failOnRuntimeSave = true;

        await expectLater(
          () => harness.service.submitTask('Write docs'),
          throwsStateError,
        );

        expect(harness.store.events, isEmpty);
        expect(
          harness.service.lastSnapshot?.errorMessage,
          contains('runtime save'),
        );
      },
    );

    test('state-changing operations are serialized', () async {
      final harness = _Harness(runDelay: const Duration(milliseconds: 20));

      await Future.wait([
        harness.service.submitTask('First'),
        harness.service.submitTask('Second'),
      ]);

      expect(harness.runner.maxActiveRuns, 1);
      expect(harness.store.events.map((event) => event.eventType), [
        ActivityEventType.startTask,
        ActivityEventType.switchTask,
      ]);
    });
  });
}

final class _Harness {
  _Harness({Duration runDelay = Duration.zero})
    : store = _MemoryStore(),
      clock = _FakeClock(DateTime.utc(2026, 1, 1, 9)) {
    runner = _MemoryTransactionRunner(store, runDelay: runDelay);
    service = TrackerService(transactions: runner, clock: clock);
  }

  final _MemoryStore store;
  final _FakeClock clock;
  late final _MemoryTransactionRunner runner;
  late final TrackerService service;
}

final class _FakeClock implements Clock {
  _FakeClock(this.current);

  DateTime current;

  @override
  DateTime nowUtc() => current;
}

final class _MemoryStore {
  _MemoryStore({
    List<ActivityLogEvent>? events,
    RuntimeState? runtimeState,
    AppSettings? settings,
    this.nextId = 1,
  }) : events = events ?? [],
       runtimeState = runtimeState ?? RuntimeState(cleanShutdown: false),
       settings = settings ?? AppSettings.defaults;

  List<ActivityLogEvent> events;
  RuntimeState runtimeState;
  AppSettings settings;
  int nextId;

  _MemoryStore copy() {
    return _MemoryStore(
      events: List<ActivityLogEvent>.of(events),
      runtimeState: runtimeState,
      settings: settings,
      nextId: nextId,
    );
  }

  void replaceWith(_MemoryStore other) {
    events = other.events;
    runtimeState = other.runtimeState;
    settings = other.settings;
    nextId = other.nextId;
  }
}

final class _MemoryTransactionRunner implements TransactionRunner {
  _MemoryTransactionRunner(this._store, {this.runDelay = Duration.zero});

  final _MemoryStore _store;
  final Duration runDelay;
  bool failOnRuntimeSave = false;
  int _activeRuns = 0;
  int maxActiveRuns = 0;

  @override
  Future<T> run<T>(
    Future<T> Function(AppTransaction transaction) action,
  ) async {
    _activeRuns += 1;
    maxActiveRuns = maxActiveRuns > _activeRuns ? maxActiveRuns : _activeRuns;
    final workingCopy = _store.copy();

    try {
      if (runDelay > Duration.zero) {
        await Future<void>.delayed(runDelay);
      }
      final result = await action(
        _MemoryTransaction(workingCopy, failOnRuntimeSave: failOnRuntimeSave),
      );
      _store.replaceWith(workingCopy);
      return result;
    } finally {
      _activeRuns -= 1;
    }
  }
}

final class _MemoryTransaction implements AppTransaction {
  _MemoryTransaction(_MemoryStore store, {required bool failOnRuntimeSave})
    : activityLog = _MemoryActivityLogRepository(store),
      runtimeState = _MemoryRuntimeStateRepository(
        store,
        failOnSave: failOnRuntimeSave,
      ),
      settings = _MemorySettingsRepository(store);

  @override
  final ActivityLogRepository activityLog;

  @override
  final RuntimeStateRepository runtimeState;

  @override
  final SettingsRepository settings;
}

final class _MemoryActivityLogRepository implements ActivityLogRepository {
  _MemoryActivityLogRepository(this._store);

  final _MemoryStore _store;

  @override
  Future<ActivityLogEvent> append(ActivityLogEvent event) async {
    final savedEvent = event.withId(_store.nextId++);
    _store.events.add(savedEvent);
    return savedEvent;
  }

  @override
  Future<List<ActivityLogEvent>> allEvents() async {
    return orderActivityEvents(_store.events);
  }
}

final class _MemoryRuntimeStateRepository implements RuntimeStateRepository {
  _MemoryRuntimeStateRepository(this._store, {required this.failOnSave});

  final _MemoryStore _store;
  final bool failOnSave;

  @override
  Future<RuntimeState> read() async => _store.runtimeState;

  @override
  Future<void> save(RuntimeState state) async {
    if (failOnSave) {
      throw StateError('runtime save failed');
    }
    _store.runtimeState = state;
  }
}

final class _MemorySettingsRepository implements SettingsRepository {
  _MemorySettingsRepository(this._store);

  final _MemoryStore _store;

  @override
  Future<AppSettings> read() async => _store.settings;

  @override
  Future<void> save(AppSettings settings) async {
    _store.settings = settings;
  }
}
