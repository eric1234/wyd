import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('ScreenSaverIdleUserIdleDetector', () {
    test('returns null when idle duration probe is unavailable', () async {
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => null,
      );

      expect(detector, isNull);
    });

    test('returns null when idle duration probe fails', () async {
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => throw StateError('probe failed'),
      );

      expect(detector, isNull);
    });

    test('logs unsupported D-Bus idle probes without error noise', () async {
      final logger = _CapturingDiagnosticLogger();

      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => throw DBusNotSupportedException(
          DBusMethodErrorResponse(
            'org.freedesktop.DBus.Error.NotSupported',
            const [DBusString('method is not supported')],
          ),
        ),
        logger: logger,
      );

      expect(detector, isNull);
      expect(logger.errors, isEmpty);
      expect(logger.debugMessages, hasLength(1));
      expect(logger.debugMessages.single, contains('unavailable'));
      expect(logger.debugMessages.single, contains('injected reader'));
    });

    test('logs unexpected idle probe failures as errors', () async {
      final logger = _CapturingDiagnosticLogger();

      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => throw StateError('probe failed'),
        logger: logger,
      );

      expect(detector, isNull);
      expect(logger.debugMessages, isEmpty);
      expect(logger.errors, hasLength(1));
      expect(
        logger.errors.single.message,
        'ScreenSaver idle detector probe failed for injected reader',
      );
      expect(logger.errors.single.error, isA<StateError>());
    });

    test('defers by remaining idle duration', () async {
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => const Duration(seconds: 2),
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, const Duration(seconds: 3));
    });

    test('allows prompt when idle duration is sufficient', () async {
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async => const Duration(seconds: 5),
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });

    test('fails open when idle duration check throws', () async {
      var calls = 0;
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        getIdleDuration: () async {
          calls += 1;
          if (calls == 1) {
            return Duration.zero;
          }
          throw StateError('check failed');
        },
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });

    test('fails open when idle duration check times out', () async {
      var calls = 0;
      final detector = await ScreenSaverIdleUserIdleDetector.create(
        requestTimeout: const Duration(milliseconds: 10),
        getIdleDuration: () {
          calls += 1;
          if (calls == 1) {
            return Future.value(Duration.zero);
          }
          return Completer<Duration?>().future;
        },
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });

    test('parses integer D-Bus idle response values as milliseconds', () {
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusUint64(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusUint32(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt64(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt32(20),
        ]),
        const Duration(milliseconds: 20),
      );
    });

    test('parses tuple and variant wrapped D-Bus idle values', () {
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          DBusStruct([const DBusUint32(20)]),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          DBusVariant(DBusStruct([const DBusUint32(20)])),
        ]),
        const Duration(milliseconds: 20),
      );
    });

    test('treats negative D-Bus idle response values as unavailable', () {
      expect(
        ScreenSaverIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt64(-1),
        ]),
        isNull,
      );
    });

    test('defines KDE freedesktop ScreenSaver sources', () {
      final sources = ScreenSaverIdleUserIdleDetector.knownSources;

      expect(
        sources.map((source) => source.serviceName),
        everyElement('org.freedesktop.ScreenSaver'),
      );
      expect(
        sources.map((source) => source.interfaceName),
        everyElement('org.freedesktop.ScreenSaver'),
      );
      expect(sources.map((source) => source.objectPath.value), [
        '/ScreenSaver',
        '/org/freedesktop/ScreenSaver',
      ]);
    });
  });
}

final class _CapturingDiagnosticLogger implements DiagnosticLogger {
  final debugMessages = <String>[];
  final errors = <_LoggedError>[];

  @override
  void debug(String message) {
    debugMessages.add(message);
  }

  @override
  void error(String message, Object error, StackTrace stackTrace) {
    errors.add(_LoggedError(message, error, stackTrace));
  }
}

final class _LoggedError {
  const _LoggedError(this.message, this.error, this.stackTrace);

  final String message;
  final Object error;
  final StackTrace stackTrace;
}
