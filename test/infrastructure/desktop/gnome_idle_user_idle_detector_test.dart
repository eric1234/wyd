import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('GnomeIdleUserIdleDetector', () {
    test('returns null when idle duration probe is unavailable', () async {
      final detector = await GnomeIdleUserIdleDetector.create(
        getIdleDuration: () async => null,
      );

      expect(detector, isNull);
    });

    test('returns null when idle duration probe fails', () async {
      final detector = await GnomeIdleUserIdleDetector.create(
        getIdleDuration: () async => throw StateError('probe failed'),
      );

      expect(detector, isNull);
    });

    test('defers by remaining idle duration', () async {
      final detector = await GnomeIdleUserIdleDetector.create(
        getIdleDuration: () async => const Duration(seconds: 2),
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, const Duration(seconds: 3));
    });

    test('allows prompt when idle duration is sufficient', () async {
      final detector = await GnomeIdleUserIdleDetector.create(
        getIdleDuration: () async => const Duration(seconds: 5),
      );

      final deferral = await detector!.promptDeferralFor(
        const Duration(seconds: 5),
      );

      expect(deferral, isNull);
    });

    test('fails open when idle duration check throws', () async {
      var calls = 0;
      final detector = await GnomeIdleUserIdleDetector.create(
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
      final detector = await GnomeIdleUserIdleDetector.create(
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

    test('parses integer D-Bus idle response values', () {
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusUint64(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusUint32(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt64(20),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt32(20),
        ]),
        const Duration(milliseconds: 20),
      );
    });

    test('parses tuple and variant wrapped D-Bus idle response values', () {
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          DBusStruct([const DBusUint64(20)]),
        ]),
        const Duration(milliseconds: 20),
      );
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          DBusVariant(DBusStruct([const DBusUint64(20)])),
        ]),
        const Duration(milliseconds: 20),
      );
    });

    test('treats negative D-Bus idle response values as unavailable', () {
      expect(
        GnomeIdleUserIdleDetector.idleDurationFromDbusReturnValues([
          const DBusInt64(-1),
        ]),
        isNull,
      );
    });
  });
}
