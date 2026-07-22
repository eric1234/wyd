import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('LifecycleCoordinator', () {
    for (final testCase in const [
      (kind: LifecycleEventKind.lock, source: ActivitySource.systemLock),
      (kind: LifecycleEventKind.sleep, source: ActivitySource.systemSleep),
    ]) {
      test(
        '${testCase.kind.name} stops active task and requests prompt',
        () async {
          final harness = _Harness();
          await harness.service.submitTask('Write docs');
          final directives = <LifecycleUiDirective>[];
          harness.coordinator.directives.listen(directives.add);

          await harness.coordinator.handle(harness.event(testCase.kind));

          expect(harness.store.events.last.source, testCase.source);
          expect(
            directives.single.disposition,
            LifecycleUiDisposition.showPrompt,
          );
          expect(directives.single.activeTask, isNull);
        },
      );
    }

    test('idle lock leaves UI unchanged', () async {
      final harness = _Harness();
      final directives = <LifecycleUiDirective>[];
      harness.coordinator.directives.listen(directives.add);

      await harness.coordinator.handle(harness.event(LifecycleEventKind.lock));

      expect(harness.store.events, isEmpty);
      expect(directives.single.disposition, LifecycleUiDisposition.leaveUi);
    });

    test('rapid lock shutdown cancellation restores pending prompt', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      final dispositions = <LifecycleUiDisposition>[];
      harness.coordinator.directives.listen((value) {
        dispositions.add(value.disposition);
      });

      await harness.coordinator.handle(harness.event(LifecycleEventKind.lock));
      await harness.coordinator.handle(
        harness.event(LifecycleEventKind.shutdown),
      );
      await harness.coordinator.handle(
        harness.event(LifecycleEventKind.shutdownCancelled),
      );

      expect(harness.store.events, hasLength(2));
      expect(harness.store.events.last.source, ActivitySource.systemLock);
      expect(harness.store.runtimeState.cleanShutdown, isTrue);
      expect(dispositions, [
        LifecycleUiDisposition.showPrompt,
        LifecycleUiDisposition.hidePrompt,
        LifecycleUiDisposition.restorePrompt,
      ]);
    });

    test('cancelled idle shutdown does not restore prompt', () async {
      final harness = _Harness();
      final dispositions = <LifecycleUiDisposition>[];
      harness.coordinator.directives.listen((value) {
        dispositions.add(value.disposition);
      });

      await harness.coordinator.handle(
        harness.event(LifecycleEventKind.shutdown),
      );
      await harness.coordinator.handle(
        harness.event(LifecycleEventKind.shutdownCancelled),
      );

      expect(dispositions, [
        LifecycleUiDisposition.hidePrompt,
        LifecycleUiDisposition.leaveUi,
      ]);
    });

    test(
      'queued submit is observed by shutdown cancellation decision',
      () async {
        final harness = _Harness(runDelay: const Duration(milliseconds: 20));
        final dispositions = <LifecycleUiDisposition>[];
        harness.coordinator.directives.listen((value) {
          dispositions.add(value.disposition);
        });

        final submit = harness.service.submitTask('Queued task');
        final shutdown = harness.coordinator.handle(
          harness.event(LifecycleEventKind.shutdown),
        );
        await Future.wait([submit, shutdown]);
        await harness.coordinator.handle(
          harness.event(LifecycleEventKind.shutdownCancelled),
        );

        expect(harness.store.events.map((event) => event.eventType), [
          ActivityEventType.startTask,
          ActivityEventType.stopTask,
        ]);
        expect(dispositions.last, LifecycleUiDisposition.restorePrompt);
      },
    );

    test('termination is terminal even when persistence fails', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.runner.failOnRuntimeSave = true;

      await expectLater(
        harness.coordinator.handle(
          harness.event(LifecycleEventKind.termination),
        ),
        throwsStateError,
      );
      expect(harness.coordinator.isTerminal, isTrue);

      await harness.coordinator.handle(harness.event(LifecycleEventKind.lock));
      expect(harness.store.events, hasLength(1));
    });

    test('failed event does not poison later handling', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.runner.failOnRuntimeSave = true;
      await expectLater(
        harness.coordinator.handle(harness.event(LifecycleEventKind.lock)),
        throwsStateError,
      );
      harness.runner.failOnRuntimeSave = false;

      await harness.coordinator.handle(harness.event(LifecycleEventKind.lock));

      expect(harness.store.events.last.source, ActivitySource.systemLock);
    });

    test('queued event runs after an earlier unawaited failure', () async {
      final harness = _Harness();
      await harness.service.submitTask('Write docs');
      harness.runner.failOnRuntimeSave = true;

      final failed = harness.coordinator.handle(
        harness.event(LifecycleEventKind.lock),
      );
      final failedExpectation = expectLater(failed, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      harness.runner.failOnRuntimeSave = false;
      final next = harness.coordinator.handle(
        harness.event(LifecycleEventKind.lock),
      );

      await failedExpectation;
      await next;
      expect(harness.store.events.last.source, ActivitySource.systemLock);
    });
  });
}

final class _Harness {
  _Harness({Duration runDelay = Duration.zero})
    : clock = _FakeClock(DateTime.utc(2026, 1, 1, 9)),
      store = _Store(),
      runner = _Runner(_Store(), runDelay: runDelay) {
    runner.store = store;
    service = TrackerService(transactions: runner, clock: clock);
    coordinator = LifecycleCoordinator(trackerService: service);
  }

  final _FakeClock clock;
  final _Store store;
  final _Runner runner;
  late final TrackerService service;
  late final LifecycleCoordinator coordinator;

  LifecycleEventOccurrence event(LifecycleEventKind kind) {
    return LifecycleEventOccurrence(kind: kind, occurredAtUtc: clock.current);
  }
}

final class _FakeClock implements Clock {
  _FakeClock(this.current);
  DateTime current;
  @override
  DateTime nowUtc() => current;
}

final class _Store {
  List<ActivityLogEvent> events = [];
  RuntimeState runtimeState = RuntimeState(cleanShutdown: false);
  AppSettings settings = AppSettings.defaults;
  int nextId = 1;
}

final class _Runner implements TransactionRunner {
  _Runner(this.store, {required this.runDelay});
  _Store store;
  final Duration runDelay;
  bool failOnRuntimeSave = false;

  @override
  Future<T> run<T>(
    Future<T> Function(AppTransaction transaction) action,
  ) async {
    if (runDelay > Duration.zero) await Future<void>.delayed(runDelay);
    final events = List<ActivityLogEvent>.from(store.events);
    final state = store.runtimeState;
    final transaction = _Transaction(
      store,
      failOnRuntimeSave: failOnRuntimeSave,
    );
    try {
      return await action(transaction);
    } catch (_) {
      store.events = events;
      store.runtimeState = state;
      rethrow;
    }
  }
}

final class _Transaction implements AppTransaction {
  _Transaction(this.store, {required bool failOnRuntimeSave})
    : activityLog = _ActivityLog(store),
      runtimeState = _RuntimeState(store, failOnSave: failOnRuntimeSave),
      settings = _Settings(store);

  final _Store store;
  @override
  final ActivityLogRepository activityLog;
  @override
  final RuntimeStateRepository runtimeState;
  @override
  final SettingsRepository settings;
  @override
  TaskTagRepository get taskTags => throw UnimplementedError();
  @override
  ReportPreferencesRepository get reportPreferences =>
      throw UnimplementedError();
}

final class _ActivityLog implements ActivityLogRepository {
  _ActivityLog(this.store);
  final _Store store;
  @override
  Future<ActivityLogEvent> append(ActivityLogEvent event) async {
    final stored = event.withId(store.nextId++);
    store.events.add(stored);
    return stored;
  }

  @override
  Future<ActivityLogEvent?> latestEvent() async =>
      store.events.isEmpty ? null : store.events.last;
  @override
  Future<List<ActivityLogEvent>> taskEventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async => List.of(store.events.where((event) => event.opensTask));
  @override
  Future<List<ActivityLogEvent>> allEvents() async => List.of(store.events);
  @override
  Future<ActivityLogEvent?> latestEventBefore(DateTime beforeUtc) async => null;
  @override
  Future<List<ActivityLogEvent>> eventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async => List.of(store.events);
}

final class _RuntimeState implements RuntimeStateRepository {
  _RuntimeState(this.store, {required this.failOnSave});
  final _Store store;
  final bool failOnSave;
  @override
  Future<RuntimeState> read() async => store.runtimeState;
  @override
  Future<void> save(RuntimeState state) async {
    if (failOnSave) throw StateError('runtime save failed');
    store.runtimeState = state;
  }
}

final class _Settings implements SettingsRepository {
  _Settings(this.store);
  final _Store store;
  @override
  Future<AppSettings> read() async => store.settings;
  @override
  Future<void> save(AppSettings settings) async => store.settings = settings;
}
