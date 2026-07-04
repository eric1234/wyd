import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('LinuxLogindLifecyclePowerAdapter', () {
    test('holds sleep inhibitor until acknowledged sleep completes', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      PowerEventOccurrence? occurrence;
      final callbackCompleter = Completer<void>();
      await harness.adapter.initialize(() async {});
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
      await harness.adapter.initialize(() async {});
      await harness.adapter.initializeAcknowledged((_) async {});

      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, true);
      await harness.inhibitors.first.releasedFuture;
      harness.emitLogind(LinuxLogindSignalKind.prepareForSleep, false);
      await _waitUntil(() => harness.inhibitors.length == 2);

      expect(harness.inhibitors.first.released, isTrue);
      expect(harness.inhibitors.last.released, isFalse);
    });

    test(
      'holds shutdown inhibitor until lifecycle callback completes',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final terminationCompleter = Completer<void>();
        var terminationRequests = 0;
        await harness.adapter.initialize(() {
          terminationRequests += 1;
          return terminationCompleter.future;
        });
        await harness.adapter.initializeAcknowledged((_) async {});

        harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
        await _waitUntil(() => terminationRequests == 1);

        expect(harness.inhibitors.single.released, isFalse);

        terminationCompleter.complete();
        await harness.inhibitors.single.releasedFuture;

        expect(harness.inhibitors.single.released, isTrue);
      },
    );

    test('reacquires inhibitor after cancelled shutdown', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.adapter.initialize(() async {});
      await harness.adapter.initializeAcknowledged((_) async {});

      harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, true);
      await harness.inhibitors.first.releasedFuture;
      harness.emitLogind(LinuxLogindSignalKind.prepareForShutdown, false);
      await _waitUntil(() => harness.inhibitors.length == 2);

      expect(harness.inhibitors.first.released, isTrue);
      expect(harness.inhibitors.last.released, isFalse);
    });

    test('routes screen lock signals through acknowledged callback', () async {
      final lockSource = LinuxDbusPowerEventAdapter.knownSources.firstWhere(
        (source) => source.isLockSource,
      );
      final harness = await _Harness.create(lockSources: [lockSource]);
      addTearDown(harness.dispose);
      final occurrences = <PowerEventOccurrence>[];
      await harness.adapter.initialize(() async {});
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

    test('dispose cancels resources and releases inhibitor', () async {
      final harness = await _Harness.create();
      await harness.adapter.initialize(() async {});
      await harness.adapter.initializeAcknowledged((_) async {});

      await harness.adapter.dispose();

      expect(harness.inhibitors.single.released, isTrue);
      expect(harness.closeRequests, 1);
    });

    test(
      'returns null and closes resources when inhibitor acquisition fails',
      () async {
        var closeRequests = 0;
        final adapter = await LinuxLogindLifecyclePowerAdapter.create(
          acquireInhibitor: () async => throw StateError('inhibit failed'),
          logindSignalValueStreamFactory: (_) => const Stream.empty(),
          lockSources: const [],
          close: () async {
            closeRequests += 1;
          },
        );

        expect(adapter, isNull);
        expect(closeRequests, 1);
      },
    );
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
  }) async {
    final inhibitors = <_FakeInhibitor>[];
    final logindControllers =
        <LinuxLogindSignalKind, StreamController<List<DBusValue>>>{};
    final lockControllers =
        <LinuxDbusPowerEventSource, StreamController<List<DBusValue>>>{};
    var closeRequests = 0;
    final adapter = await LinuxLogindLifecyclePowerAdapter.create(
      acquireInhibitor: () async {
        final inhibitor = _FakeInhibitor();
        inhibitors.add(inhibitor);
        return inhibitor;
      },
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
