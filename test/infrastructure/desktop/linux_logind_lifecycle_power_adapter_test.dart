import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('LinuxLogindLifecyclePowerAdapter', () {
    test('does not acquire inhibitor during create', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      expect(harness.inhibitors, isEmpty);
      expect(harness.closeRequests, 0);
    });

    test('holds sleep inhibitor until acknowledged sleep completes', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      PowerEventOccurrence? occurrence;
      final callbackCompleter = Completer<void>();
      await harness.adapter.initializeAcknowledged((value) {
        occurrence = value;
        return callbackCompleter.future;
      });

      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
      await _waitUntil(() => occurrence != null);

      expect(occurrence!.event, PowerEvent.sleep);
      expect(occurrence!.occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 30));
      expect(harness.inhibitors.single.released, isFalse);

      callbackCompleter.complete();
      await harness.inhibitors.single.releasedFuture;

      expect(harness.inhibitors.single.released, isTrue);
    });

    test('reacquires inhibitor after resume', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.adapter.initializeAcknowledged((_) async {});

      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
      await harness.inhibitors.first.releasedFuture;
      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, false);
      await _waitUntil(() => harness.inhibitors.length == 2);

      expect(harness.inhibitors.first.released, isTrue);
      expect(harness.inhibitors.last.released, isFalse);
    });

    test(
      'holds shutdown inhibitor until acknowledged callback completes',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        PowerEventOccurrence? occurrence;
        final callbackCompleter = Completer<void>();
        await harness.adapter.initializeAcknowledged((value) {
          occurrence = value;
          return callbackCompleter.future;
        });

        harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
        await _waitUntil(() => occurrence != null);

        expect(occurrence!.event, PowerEvent.shutdown);
        expect(occurrence!.occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 30));
        expect(harness.inhibitors.single.released, isFalse);

        callbackCompleter.complete();
        await harness.inhibitors.single.releasedFuture;

        expect(harness.inhibitors.single.released, isTrue);
      },
    );

    test('reacquires inhibitor after cancelled shutdown', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
      });

      harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
      await harness.inhibitors.first.releasedFuture;
      harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, false);
      await _waitUntil(() => occurrences.length == 2);

      expect(harness.inhibitors.first.released, isTrue);
      expect(harness.inhibitors.last.released, isFalse);
      expect(occurrences.map((occurrence) => occurrence.event), [
        PowerEvent.shutdown,
        PowerEvent.shutdownCancelled,
      ]);
    });

    test('does not emit cancellation without shutdown preparation', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
      });

      harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, false);
      await Future<void>.delayed(Duration.zero);

      expect(occurrences, isEmpty);
      expect(harness.inhibitors, hasLength(1));
      expect(harness.inhibitors.single.released, isFalse);
    });

    test(
      'starts listeners before initial inhibitor acquisition completes',
      () async {
        final inhibitorCompleter = Completer<_FakeInhibitor>();
        final harness = await _Harness.create(
          acquireInhibitor: (inhibitors) async {
            final inhibitor = await inhibitorCompleter.future;
            inhibitors.add(inhibitor);
            return inhibitor;
          },
        );
        addTearDown(harness.dispose);
        final occurrences = <PowerEventOccurrence>[];

        final initializeFuture = harness.adapter.initializeAcknowledged((
          occurrence,
        ) async {
          occurrences.add(occurrence);
        });

        expect(
          harness.logindControllers.keys,
          containsAll(LinuxLogindSignalKind.values),
        );
        harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
        await _waitUntil(() => occurrences.isNotEmpty);

        expect(occurrences.single.event, PowerEvent.shutdown);
        expect(harness.inhibitors, isEmpty);

        inhibitorCompleter.complete(_FakeInhibitor());
        await initializeFuture;

        expect(harness.inhibitors.single.released, isTrue);
      },
    );

    test('routes screen lock signals through acknowledged callback', () async {
      final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
        (source) => source.isLockSource,
      );
      final harness = await _Harness.create(lockSources: [lockSource]);
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
      });

      harness.emitLock(lockSource, false);
      await Future<void>.delayed(Duration.zero);
      harness.emitLock(lockSource, true);
      await _waitUntil(() => occurrences.isNotEmpty);

      expect(occurrences, hasLength(1));
      expect(occurrences.single.event, PowerEvent.lock);
      expect(occurrences.single.occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 30));
      expect(harness.inhibitors.single.released, isFalse);
    });

    test('serializes events while an acknowledgement is pending', () async {
      final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
        (source) => source.isLockSource,
      );
      final harness = await _Harness.create(lockSources: [lockSource]);
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      final sleepCompleter = Completer<void>();
      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
        if (occurrence.event == PowerEvent.sleep) {
          await sleepCompleter.future;
        }
      });

      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
      await _waitUntil(() => occurrences.isNotEmpty);
      harness.emitLock(lockSource, true);
      await Future<void>.delayed(Duration.zero);

      expect(occurrences.map((occurrence) => occurrence.event), [
        PowerEvent.sleep,
      ]);

      sleepCompleter.complete();
      await _waitUntil(() => occurrences.length == 2);

      expect(occurrences.map((occurrence) => occurrence.event), [
        PowerEvent.sleep,
        PowerEvent.lock,
      ]);
    });

    test(
      'callback failure releases inhibitor and preserves event chain',
      () async {
        final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
          (source) => source.isLockSource,
        );
        final harness = await _Harness.create(lockSources: [lockSource]);
        addTearDown(harness.dispose);
        final occurrences = <PowerEventOccurrence>[];
        await harness.adapter.initializeAcknowledged((occurrence) async {
          occurrences.add(occurrence);
          if (occurrence.event == PowerEvent.sleep) {
            throw StateError('persistence failed');
          }
        });

        harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
        await harness.inhibitors.single.releasedFuture;
        harness.emitLock(lockSource, true);
        await _waitUntil(() => occurrences.length == 2);

        expect(harness.inhibitors.single.released, isTrue);
        expect(occurrences.map((occurrence) => occurrence.event), [
          PowerEvent.sleep,
          PowerEvent.lock,
        ]);
      },
    );

    test(
      'reacquires inhibitor before acknowledging shutdown cancellation',
      () async {
        final reacquireCompleter = Completer<LinuxLogindInhibitor>();
        var acquireRequests = 0;
        final harness = await _Harness.create(
          acquireInhibitor: (inhibitors) {
            acquireRequests += 1;
            if (acquireRequests == 1) {
              final inhibitor = _FakeInhibitor();
              inhibitors.add(inhibitor);
              return Future.value(inhibitor);
            }
            return reacquireCompleter.future;
          },
        );
        addTearDown(harness.dispose);
        final occurrences = <PowerEventOccurrence>[];
        await harness.adapter.initializeAcknowledged((occurrence) async {
          occurrences.add(occurrence);
        });

        harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
        await harness.inhibitors.single.releasedFuture;
        harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, false);
        await _waitUntil(() => acquireRequests == 2);

        expect(occurrences.map((occurrence) => occurrence.event), [
          PowerEvent.shutdown,
        ]);

        final reacquiredInhibitor = _FakeInhibitor();
        harness.inhibitors.add(reacquiredInhibitor);
        reacquireCompleter.complete(reacquiredInhibitor);
        await _waitUntil(() => occurrences.length == 2);

        expect(occurrences.map((occurrence) => occurrence.event), [
          PowerEvent.shutdown,
          PowerEvent.shutdownCancelled,
        ]);
        expect(reacquiredInhibitor.released, isFalse);
      },
    );

    test('dispose is idempotent and releases resources once', () async {
      final harness = await _Harness.create();
      await harness.adapter.initializeAcknowledged((_) async {});

      await harness.adapter.dispose();
      await harness.adapter.dispose();

      expect(harness.inhibitors.single.released, isTrue);
      expect(harness.closeRequests, 1);
    });

    test('reacquire timeout does not block later events or dispose', () async {
      final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
        (source) => source.isLockSource,
      );
      final lateInhibitorCompleter = Completer<LinuxLogindInhibitor>();
      var acquireRequests = 0;
      final harness = await _Harness.create(
        lockSources: [lockSource],
        requestTimeout: const Duration(milliseconds: 1),
        acquireInhibitor: (inhibitors) {
          acquireRequests += 1;
          if (acquireRequests == 1) {
            final inhibitor = _FakeInhibitor();
            inhibitors.add(inhibitor);
            return Future.value(inhibitor);
          }
          return lateInhibitorCompleter.future;
        },
      );
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
      });

      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
      await harness.inhibitors.first.releasedFuture;
      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, false);
      await _waitUntil(() => acquireRequests == 2);
      harness.emitLock(lockSource, true);
      await _waitUntil(
        () => occurrences.any(
          (occurrence) => occurrence.event == PowerEvent.lock,
        ),
      );

      await harness.adapter.dispose().timeout(const Duration(milliseconds: 50));
      final lateInhibitor = _FakeInhibitor();
      lateInhibitorCompleter.complete(lateInhibitor);
      await lateInhibitor.releasedFuture;

      expect(lateInhibitor.released, isTrue);
    });

    test(
      'startup acquisition failure fails open after listeners start',
      () async {
        final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
          (source) => source.isLockSource,
        );
        final harness = await _Harness.create(
          lockSources: [lockSource],
          acquireInhibitor: (_) async => throw StateError('inhibit failed'),
        );
        addTearDown(harness.dispose);
        final occurrences = <PowerEventOccurrence>[];

        await harness.adapter.initializeAcknowledged((occurrence) async {
          occurrences.add(occurrence);
        });

        expect(harness.inhibitors, isEmpty);
        expect(harness.closeRequests, 0);

        harness.emitLock(lockSource, true);
        await _waitUntil(() => occurrences.isNotEmpty);

        expect(occurrences.single.event, PowerEvent.lock);
        expect(harness.closeRequests, 0);
      },
    );

    test('startup timeout fails open and releases late inhibitor', () async {
      final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
        (source) => source.isLockSource,
      );
      final lateInhibitorCompleter = Completer<LinuxLogindInhibitor>();
      final harness = await _Harness.create(
        lockSources: [lockSource],
        requestTimeout: const Duration(milliseconds: 1),
        acquireInhibitor: (_) => lateInhibitorCompleter.future,
      );
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];

      await harness.adapter.initializeAcknowledged((occurrence) async {
        occurrences.add(occurrence);
      });

      expect(harness.inhibitors, isEmpty);
      expect(harness.closeRequests, 0);

      harness.emitLock(lockSource, true);
      await _waitUntil(() => occurrences.isNotEmpty);

      final lateInhibitor = _FakeInhibitor();
      lateInhibitorCompleter.complete(lateInhibitor);
      await lateInhibitor.releasedFuture;

      expect(lateInhibitor.released, isTrue);
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for async adapter action.');
}

final class _Harness {
  _Harness({
    required this.adapter,
    required this.inhibitors,
    required this.logindControllers,
    required this.lockControllers,
    required this.closeRequestsRef,
  });

  final LinuxLogindLifecyclePowerAdapter adapter;
  final List<_FakeInhibitor> inhibitors;
  final Map<LinuxLogindSignalKind, StreamController<List<DBusValue>>>
  logindControllers;
  final Map<LinuxDbusPowerEventSource, StreamController<List<DBusValue>>>
  lockControllers;
  final int Function() closeRequestsRef;

  int get closeRequests => closeRequestsRef();

  static Future<_Harness> create({
    Iterable<LinuxDbusPowerEventSource> lockSources = const [],
    Duration requestTimeout =
        LinuxLogindLifecyclePowerAdapter.defaultRequestTimeout,
    Future<LinuxLogindInhibitor> Function(List<_FakeInhibitor> inhibitors)?
    acquireInhibitor,
  }) async {
    final inhibitors = <_FakeInhibitor>[];
    final logindControllers =
        <LinuxLogindSignalKind, StreamController<List<DBusValue>>>{};
    final lockControllers =
        <LinuxDbusPowerEventSource, StreamController<List<DBusValue>>>{};
    var closeRequests = 0;
    final adapter = await LinuxLogindLifecyclePowerAdapter.create(
      acquireInhibitor: acquireInhibitor == null
          ? () async {
              final inhibitor = _FakeInhibitor();
              inhibitors.add(inhibitor);
              return inhibitor;
            }
          : () => acquireInhibitor(inhibitors),
      logindSignalValueStreamFactory: (signal) {
        return logindControllers
            .putIfAbsent(
              signal.kind,
              () => StreamController<List<DBusValue>>.broadcast(),
            )
            .stream;
      },
      lockSources: lockSources,
      probeLockSource: (_) async => true,
      lockSignalValueStreamFactory: (source) {
        return lockControllers
            .putIfAbsent(
              source,
              () => StreamController<List<DBusValue>>.broadcast(),
            )
            .stream;
      },
      nowUtc: () => DateTime.utc(2026, 1, 1, 9, 30),
      requestTimeout: requestTimeout,
      close: () async {
        closeRequests += 1;
      },
      logger: _CapturingDiagnosticLogger(),
    );

    return _Harness(
      adapter: adapter!,
      inhibitors: inhibitors,
      logindControllers: logindControllers,
      lockControllers: lockControllers,
      closeRequestsRef: () => closeRequests,
    );
  }

  void emitLogind(LinuxLogindSignalKind kind, bool value) {
    logindControllers[kind]!.add([DBusBoolean(value)]);
  }

  void emitLock(LinuxDbusPowerEventSource source, bool value) {
    lockControllers[source]!.add([DBusBoolean(value)]);
  }

  Future<void> dispose() async {
    await adapter.dispose();
    for (final controller in logindControllers.values) {
      await controller.close();
    }
    for (final controller in lockControllers.values) {
      await controller.close();
    }
  }
}

final class _FakeInhibitor implements LinuxLogindInhibitor {
  final Completer<void> _released = Completer<void>();
  bool released = false;

  Future<void> get releasedFuture => _released.future;

  @override
  Future<void> release() async {
    if (released) {
      return;
    }
    released = true;
    _released.complete();
  }
}

final class _CapturingDiagnosticLogger implements DiagnosticLogger {
  @override
  void debug(String message) {}

  @override
  void error(String message, Object error, StackTrace stackTrace) {}
}
