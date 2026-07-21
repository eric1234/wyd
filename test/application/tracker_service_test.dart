import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';

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

    test('stopTask records explicit occurrence timestamp', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);
      final sleepAt = DateTime.utc(2026, 1, 1, 9, 30);

      final snapshot = await harness.service.stopTask(
        source: ActivitySource.systemSleep,
        occurredAtUtc: sleepAt,
      );

      expect(snapshot.activeTask, isNull);
      expect(harness.store.events.last.eventType, ActivityEventType.stopTask);
      expect(harness.store.events.last.source, ActivitySource.systemSleep);
      expect(harness.store.events.last.occurredAtUtc, sleepAt);
      expect(harness.store.events.last.createdAtUtc, harness.clock.current);
    });

    test('stopTask does not place stop before active task start', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      final taskStartedAt = harness.clock.current;
      final sleepAt = taskStartedAt.subtract(const Duration(minutes: 1));

      final snapshot = await harness.service.stopTask(
        source: ActivitySource.systemSleep,
        occurredAtUtc: sleepAt,
      );

      expect(snapshot.activeTask, isNull);
      expect(harness.store.events.last.occurredAtUtc, taskStartedAt);
    });

    test('system boundary stop returns after the atomic transition', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);
      final sleepAt = DateTime.utc(2026, 1, 1, 9, 30);

      final result = await harness.service.stopForSystemBoundary(
        source: ActivitySource.systemSleep,
        occurredAtUtc: sleepAt,
      );

      expect(result.didStopActiveTask, isTrue);
      expect(result.activeTask, isNull);
      expect(result.runtimeState.cleanShutdown, isFalse);
      expect(harness.store.events.last.source, ActivitySource.systemSleep);
      expect(harness.store.events.last.occurredAtUtc, sleepAt);
      expect(harness.store.events.last.createdAtUtc, harness.clock.current);
      expect(harness.store.runtimeState.cleanShutdown, isFalse);
    });

    test('system boundary stop is idempotent while idle', () async {
      final harness = _Harness();

      final result = await harness.service.stopForSystemBoundary(
        source: ActivitySource.systemLock,
        occurredAtUtc: harness.clock.current,
      );

      expect(result.didStopActiveTask, isFalse);
      expect(result.activeTask, isNull);
      expect(harness.store.events, isEmpty);
    });

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

    test('exit records explicit occurrence timestamp when supplied', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 10);
      final shutdownAt = DateTime.utc(2026, 1, 1, 9, 30);

      final snapshot = await harness.service.exitRequested(
        occurredAtUtc: shutdownAt,
      );

      expect(snapshot.activeTask, isNull);
      expect(snapshot.runtimeState.cleanShutdown, isTrue);
      expect(harness.store.events.last.source, ActivitySource.exit);
      expect(harness.store.events.last.occurredAtUtc, shutdownAt);
      expect(harness.store.events.last.createdAtUtc, harness.clock.current);
    });

    test('exit does not place stop before active task start', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      final taskStartedAt = harness.clock.current;
      final shutdownAt = taskStartedAt.subtract(const Duration(minutes: 1));

      final snapshot = await harness.service.exitRequested(
        occurredAtUtc: shutdownAt,
      );

      expect(snapshot.activeTask, isNull);
      expect(harness.store.events.last.occurredAtUtc, taskStartedAt);
    });

    test(
      'system shutdown preparation commits only the boundary state',
      () async {
        final harness = _Harness();
        await harness.service.submitTask('Write docs');
        harness.clock.current = DateTime.utc(2026, 1, 1, 10);
        final shutdownAt = DateTime.utc(2026, 1, 1, 9, 30);

        final result = await harness.service.prepareForSystemShutdown(
          occurredAtUtc: shutdownAt,
        );

        expect(result.didStopActiveTask, isTrue);
        expect(result.activeTask, isNull);
        expect(result.runtimeState.cleanShutdown, isTrue);
        expect(harness.store.events.last.source, ActivitySource.exit);
        expect(harness.store.events.last.occurredAtUtc, shutdownAt);
        expect(harness.store.runtimeState.cleanShutdown, isTrue);
      },
    );

    test('system shutdown preparation marks idle state clean', () async {
      final harness = _Harness();

      final result = await harness.service.prepareForSystemShutdown(
        occurredAtUtc: harness.clock.current,
      );

      expect(result.didStopActiveTask, isFalse);
      expect(result.activeTask, isNull);
      expect(result.runtimeState.cleanShutdown, isTrue);
      expect(harness.store.events, isEmpty);
      expect(harness.store.runtimeState.cleanShutdown, isTrue);
    });

    test(
      'failed system boundary transition does not rebuild a snapshot',
      () async {
        final harness = _Harness();
        await harness.service.submitTask('Write docs');
        final lastSnapshot = harness.service.lastSnapshot;
        harness.runner.failOnRuntimeSave = true;

        await expectLater(
          () => harness.service.stopForSystemBoundary(
            source: ActivitySource.systemLock,
            occurredAtUtc: harness.clock.current,
          ),
          throwsStateError,
        );

        expect(harness.store.events, hasLength(1));
        expect(harness.service.lastSnapshot, same(lastSnapshot));
      },
    );

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

    test('empty submit does not mutate persisted state', () async {
      final harness = await _SqliteHarness.create();
      addTearDown(harness.dispose);
      final initialState = await harness.runtimeState.read();

      await expectLater(
        () => harness.service.submitTask(' \t\n '),
        throwsA(isA<TaskTextValidationException>()),
      );

      expect(await harness.activityLog.allEvents(), isEmpty);
      final state = await harness.runtimeState.read();
      expect(state.lastConfirmationAtUtc, initialState.lastConfirmationAtUtc);
      expect(state.promptState.status, initialState.promptState.status);
      expect(state.cleanShutdown, initialState.cleanShutdown);
    });

    test(
      'confirmation while prompt is visible clears pending prompt',
      () async {
        final harness = await _SqliteHarness.create();
        addTearDown(harness.dispose);
        await harness.service.submitTask('Write docs');
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);
        await harness.service.nagPromptShown();
        harness.clock.current = DateTime.utc(2026, 1, 1, 9, 16);

        final snapshot = await harness.service.submitTask('write   docs');

        expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
        expect(
          snapshot.runtimeState.lastConfirmationAtUtc,
          harness.clock.current,
        );
        expect(await harness.activityLog.allEvents(), hasLength(1));
      },
    );

    test('switch while prompt is visible clears pending prompt', () async {
      final harness = await _SqliteHarness.create();
      addTearDown(harness.dispose);
      await harness.service.submitTask('Write docs');
      await harness.service.nagPromptShown();
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 20);

      final snapshot = await harness.service.submitTask('Fix bug');

      expect(snapshot.activeTask!.taskText, 'Fix bug');
      expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
      expect(
        (await harness.activityLog.allEvents()).map((event) => event.eventType),
        [ActivityEventType.startTask, ActivityEventType.switchTask],
      );
    });

    test('nagPromptShown is a no-op while idle or already pending', () async {
      final harness = await _SqliteHarness.create();
      addTearDown(harness.dispose);

      var snapshot = await harness.service.nagPromptShown();
      expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
      expect(await harness.activityLog.allEvents(), isEmpty);

      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);
      snapshot = await harness.service.nagPromptShown();
      final shownAt = snapshot.runtimeState.promptState.shownAtUtc;
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 30);

      snapshot = await harness.service.nagPromptShown();

      expect(snapshot.runtimeState.promptState.status, PromptStatus.visible);
      expect(snapshot.runtimeState.promptState.shownAtUtc, shownAt);
    });

    test(
      'nagPromptTimedOut does not duplicate invalid timeout stops',
      () async {
        final harness = await _SqliteHarness.create();
        addTearDown(harness.dispose);

        var snapshot = await harness.service.nagPromptTimedOut();
        expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
        expect(await harness.activityLog.allEvents(), isEmpty);

        await harness.service.submitTask('Write docs');
        snapshot = await harness.service.nagPromptTimedOut();
        expect(snapshot.activeTask, isNotNull);
        expect(await harness.activityLog.allEvents(), hasLength(1));

        await harness.service.nagPromptShown();
        await harness.service.nagPromptTimedOut();
        await harness.service.nagPromptTimedOut();

        final stopEvents = (await harness.activityLog.allEvents()).where(
          (event) => event.eventType == ActivityEventType.stopTask,
        );
        expect(stopEvents, hasLength(1));
      },
    );

    test('promptClosed preserves pending prompt state', () async {
      final harness = await _SqliteHarness.create();
      addTearDown(harness.dispose);
      await harness.service.submitTask('Write docs');
      harness.clock.current = DateTime.utc(2026, 1, 1, 9, 15);
      await harness.service.nagPromptShown();

      final snapshot = await harness.service.promptClosed();

      expect(snapshot.runtimeState.promptState.status, PromptStatus.visible);
      expect(
        snapshot.runtimeState.promptState.shownAtUtc,
        DateTime.utc(2026, 1, 1, 9, 15),
      );
    });

    test('recovery after unclean idle shutdown appends no event', () async {
      final harness = await _SqliteHarness.create();
      addTearDown(harness.dispose);
      await harness.runtimeState.save(RuntimeState(cleanShutdown: false));

      final snapshot = await harness.service.recoverOnStartup();

      expect(snapshot.activeTask, isNull);
      expect(await harness.activityLog.allEvents(), isEmpty);
      expect(snapshot.runtimeState.promptState.status, PromptStatus.none);
    });

    test(
      'recovery falls back to active task start without confirmation',
      () async {
        final harness = await _SqliteHarness.create();
        addTearDown(harness.dispose);
        final startedAt = DateTime.utc(2026, 1, 1, 8, 45);
        await harness.activityLog.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: startedAt,
            taskText: 'Write docs',
          ),
        );
        await harness.runtimeState.save(RuntimeState(cleanShutdown: false));

        await harness.service.recoverOnStartup();

        final events = await harness.activityLog.allEvents();
        expect(events.last.source, ActivitySource.recovery);
        expect(events.last.occurredAtUtc, startedAt);
      },
    );
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

final class _SqliteHarness {
  _SqliteHarness({
    required this.database,
    required this.clock,
    required this.service,
    required this.activityLog,
    required this.runtimeState,
  });

  final AppDatabase database;
  final _FakeClock clock;
  final TrackerService service;
  final SqliteActivityLogRepository activityLog;
  final SqliteRuntimeStateRepository runtimeState;

  static Future<_SqliteHarness> create() async {
    final database = await AppDatabase.openInMemory(
      databaseFactory: databaseFactoryFfi,
    );
    final clock = _FakeClock(DateTime.utc(2026, 1, 1, 9));
    return _SqliteHarness(
      database: database,
      clock: clock,
      service: TrackerService(
        transactions: SqliteTransactionRunner(database),
        clock: clock,
      ),
      activityLog: SqliteActivityLogRepository(database.database),
      runtimeState: SqliteRuntimeStateRepository(database.database),
    );
  }

  Future<void> dispose() => database.close();
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
    Map<String, List<TaskTag>>? taskTags,
    RuntimeState? runtimeState,
    AppSettings? settings,
    this.nextId = 1,
  }) : events = events ?? [],
       taskTags = taskTags ?? {},
       runtimeState = runtimeState ?? RuntimeState(cleanShutdown: false),
       settings = settings ?? AppSettings.defaults;

  List<ActivityLogEvent> events;
  Map<String, List<TaskTag>> taskTags;
  RuntimeState runtimeState;
  AppSettings settings;
  int nextId;

  _MemoryStore copy() {
    return _MemoryStore(
      events: List<ActivityLogEvent>.of(events),
      taskTags: taskTags.map(
        (key, value) => MapEntry(key, List<TaskTag>.of(value)),
      ),
      runtimeState: runtimeState,
      settings: settings,
      nextId: nextId,
    );
  }

  void replaceWith(_MemoryStore other) {
    events = other.events;
    taskTags = other.taskTags;
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
      settings = _MemorySettingsRepository(store),
      taskTags = _MemoryTaskTagRepository(store),
      reportPreferences = const _MemoryReportPreferencesRepository();

  @override
  final ActivityLogRepository activityLog;

  @override
  final RuntimeStateRepository runtimeState;

  @override
  final SettingsRepository settings;

  @override
  final TaskTagRepository taskTags;

  @override
  final ReportPreferencesRepository reportPreferences;
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

  @override
  Future<ActivityLogEvent?> latestEvent() async {
    final events = orderActivityEvents(_store.events);
    return events.isEmpty ? null : events.last;
  }

  @override
  Future<ActivityLogEvent?> latestEventBefore(DateTime beforeUtc) async {
    final events = orderActivityEvents(_store.events)
        .where((event) => event.occurredAtUtc.isBefore(beforeUtc.toUtc()))
        .toList();
    return events.isEmpty ? null : events.last;
  }

  @override
  Future<List<ActivityLogEvent>> eventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async {
    return orderActivityEvents(_store.events)
        .where(
          (event) =>
              !event.occurredAtUtc.isBefore(fromUtc.toUtc()) &&
              !event.occurredAtUtc.isAfter(throughUtc.toUtc()),
        )
        .toList();
  }

  @override
  Future<List<ActivityLogEvent>> taskEventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async {
    return orderActivityEvents(_store.events)
        .where(
          (event) =>
              event.opensTask &&
              !event.occurredAtUtc.isBefore(fromUtc.toUtc()) &&
              !event.occurredAtUtc.isAfter(throughUtc.toUtc()),
        )
        .toList();
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

final class _MemoryTaskTagRepository implements TaskTagRepository {
  _MemoryTaskTagRepository(this._store);

  final _MemoryStore _store;

  @override
  Future<List<TaskTag>> allTags() async {
    final tags = <String, TaskTag>{};
    for (final taskTags in _store.taskTags.values) {
      for (final tag in taskTags) {
        tags.putIfAbsent(tag.normalized, () => tag);
      }
    }
    return tags.values.toList();
  }

  @override
  Future<Map<String, List<TaskTag>>> tagsForTasks(
    Iterable<String> taskTextNormalizedValues,
  ) async {
    return {
      for (final taskKey in taskTextNormalizedValues)
        if (_store.taskTags.containsKey(taskKey))
          taskKey: List<TaskTag>.of(_store.taskTags[taskKey]!),
    };
  }

  @override
  Future<TaskTag> addTag({
    required String taskTextNormalized,
    required String tagText,
  }) async {
    final tag = TaskTag.fromInput(tagText);
    final tags = _store.taskTags.putIfAbsent(taskTextNormalized, () => []);
    final existing = tags.where((item) => item.normalized == tag.normalized);
    if (existing.isNotEmpty) {
      return existing.single;
    }
    tags.add(tag);
    tags.sort((left, right) => left.normalized.compareTo(right.normalized));
    return tag;
  }

  @override
  Future<void> removeTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) async {
    _store.taskTags[taskTextNormalized]?.removeWhere(
      (tag) => tag.normalized == tagTextNormalized,
    );
  }
}

final class _MemoryReportPreferencesRepository
    implements ReportPreferencesRepository {
  const _MemoryReportPreferencesRepository();

  @override
  Future<ReportVisualizationPreferences> read() async =>
      ReportVisualizationPreferences.defaults;

  @override
  Future<void> save(ReportVisualizationPreferences preferences) async {}
}
