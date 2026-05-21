import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_idle_platform_interface/system_idle_platform_interface.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('SystemIdleUserIdleDetector', () {
    test('returns null and disposes unsupported plugin', () async {
      final plugin = _FakeSystemIdlePlugin(supported: false);
      addTearDown(plugin.closeEventControllers);

      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      expect(detector, isNull);
      expect(plugin.disposeCalls, 1);
      expect(plugin.getIdleDurationCalls, 0);
    });

    test('returns null and disposes when initialization fails', () async {
      final plugin = _FakeSystemIdlePlugin(
        initializeError: StateError('initialize failed'),
      );
      addTearDown(plugin.closeEventControllers);

      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      expect(detector, isNull);
      expect(plugin.disposeCalls, 1);
    });

    test('returns null and disposes when duration probe fails', () async {
      final plugin = _FakeSystemIdlePlugin(
        getIdleDurationError: StateError('probe failed'),
      );
      addTearDown(plugin.closeEventControllers);

      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      expect(detector, isNull);
      expect(plugin.disposeCalls, 1);
      expect(plugin.getIdleDurationCalls, 1);
    });

    test('duration mode defers by remaining idle duration', () async {
      final plugin = _FakeSystemIdlePlugin(
        idleDuration: const Duration(seconds: 2),
      );
      addTearDown(plugin.closeEventControllers);
      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, const Duration(seconds: 3));
    });

    test(
      'duration mode allows prompt when idle duration is sufficient',
      () async {
        final plugin = _FakeSystemIdlePlugin(
          idleDuration: const Duration(seconds: 5),
        );
        addTearDown(plugin.closeEventControllers);
        final detector = await SystemIdleUserIdleDetector.create(
          pluginFactory: () => plugin,
        );

        final deferral = await detector!.promptDeferralFor(
          const Duration(seconds: 5),
        );

        expect(deferral, isNull);
      },
    );

    test('creates event mode when duration query is unavailable', () async {
      final plugin = _FakeSystemIdlePlugin(idleDuration: null);
      addTearDown(plugin.closeEventControllers);

      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      expect(detector, isNotNull);
      expect(plugin.disposeCalls, 0);
    });

    test(
      'event mode subscribes with threshold and rechecks before idle event',
      () async {
        final plugin = _FakeSystemIdlePlugin(idleDuration: null);
        addTearDown(plugin.closeEventControllers);
        final detector = await SystemIdleUserIdleDetector.create(
          pluginFactory: () => plugin,
        );

        final deferral = await detector!.promptDeferralFor(
          const Duration(seconds: 5),
        );

        expect(deferral, const Duration(seconds: 1));
        expect(plugin.eventThresholds, [const Duration(seconds: 5)]);
      },
    );

    test('event mode caps recheck delay by requested threshold', () async {
      final plugin = _FakeSystemIdlePlugin(idleDuration: null);
      addTearDown(plugin.closeEventControllers);
      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(milliseconds: 500),
      );

      expect(deferral, const Duration(milliseconds: 500));
    });

    test('event mode allows prompt after idle event', () async {
      final plugin = _FakeSystemIdlePlugin(idleDuration: null);
      addTearDown(plugin.closeEventControllers);
      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      await detector!.promptDeferralFor(const Duration(seconds: 5));
      plugin.emitIdleChanged(true);
      await Future<void>.delayed(Duration.zero);

      final deferral = await detector.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });

    test('event mode defers again after active event', () async {
      final plugin = _FakeSystemIdlePlugin(idleDuration: null);
      addTearDown(plugin.closeEventControllers);
      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      await detector!.promptDeferralFor(const Duration(seconds: 5));
      plugin.emitIdleChanged(true);
      await Future<void>.delayed(Duration.zero);
      plugin.emitIdleChanged(false);
      await Future<void>.delayed(Duration.zero);

      final deferral = await detector.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, const Duration(seconds: 1));
    });

    test(
      'event mode resubscribes and resets state when threshold changes',
      () async {
        final plugin = _FakeSystemIdlePlugin(idleDuration: null);
        addTearDown(plugin.closeEventControllers);
        final detector = await SystemIdleUserIdleDetector.create(
          pluginFactory: () => plugin,
        );

        await detector!.promptDeferralFor(const Duration(seconds: 5));
        plugin.emitIdleChanged(true);
        await Future<void>.delayed(Duration.zero);

        final deferral = await detector.promptDeferralFor(
          const Duration(seconds: 10),
        );

        expect(deferral, const Duration(seconds: 1));
        expect(plugin.eventThresholds, [
          const Duration(seconds: 5),
          const Duration(seconds: 10),
        ]);
        expect(plugin.cancelledThresholds, [const Duration(seconds: 5)]);
      },
    );

    test('event setup errors fail open', () async {
      final plugin = _FakeSystemIdlePlugin(
        idleDuration: null,
        onIdleChangedError: StateError('listen failed'),
      );
      addTearDown(plugin.closeEventControllers);
      final detector = await SystemIdleUserIdleDetector.create(
        pluginFactory: () => plugin,
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });
  });
}

final class _FakeSystemIdlePlugin extends SystemIdlePlatformInterface {
  _FakeSystemIdlePlugin({
    this.supported = true,
    this.idleDuration = Duration.zero,
    this.initializeError,
    this.getIdleDurationError,
    this.onIdleChangedError,
  });

  final bool supported;
  Duration? idleDuration;
  final Object? initializeError;
  final Object? getIdleDurationError;
  final Object? onIdleChangedError;
  final List<Duration> eventThresholds = [];
  final List<Duration> cancelledThresholds = [];
  final List<StreamController<bool>> _eventControllers = [];
  int disposeCalls = 0;
  int getIdleDurationCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> initialize() async {
    if (initializeError != null) {
      throw initializeError!;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await super.dispose();
  }

  @override
  Future<Duration?> getIdleDuration() async {
    getIdleDurationCalls += 1;
    if (getIdleDurationError != null) {
      throw getIdleDurationError!;
    }
    return idleDuration;
  }

  @override
  Stream<bool> onIdleChanged({required Duration idleDuration}) {
    if (onIdleChangedError != null) {
      throw onIdleChangedError!;
    }

    eventThresholds.add(idleDuration);
    final controller = StreamController<bool>.broadcast(
      onCancel: () {
        cancelledThresholds.add(idleDuration);
      },
    );
    _eventControllers.add(controller);
    return controller.stream;
  }

  void emitIdleChanged(bool isIdle) {
    _eventControllers.last.add(isIdle);
  }

  Future<void> closeEventControllers() async {
    for (final controller in _eventControllers) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }
}
