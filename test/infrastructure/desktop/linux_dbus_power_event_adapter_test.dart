import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('LinuxDbusPowerEventAdapter', () {
    test('maps PrepareForSleep true to sleep and false to ignored', () {
      final source = _sleepSource();

      expect(
        LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const [
          DBusBoolean(true),
        ]),
        PowerEvent.sleep,
      );
      expect(
        LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const [
          DBusBoolean(false),
        ]),
        isNull,
      );
    });

    test('maps ActiveChanged true to lock and false to ignored', () {
      final source = _lockSource();

      expect(
        LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const [
          DBusBoolean(true),
        ]),
        PowerEvent.lock,
      );
      expect(
        LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const [
          DBusBoolean(false),
        ]),
        isNull,
      );
    });

    test('defines GNOME, Cinnamon, freedesktop, and KDE lock sources', () {
      final sources = LinuxDbusPowerEventAdapter.knownSources;

      expect(
        sources.map((source) => source.serviceName),
        containsAll([
          'org.cinnamon.ScreenSaver',
          'org.gnome.ScreenSaver',
          'org.freedesktop.ScreenSaver',
          'org.kde.screensaver',
        ]),
      );
      expect(
        sources.where(
          (source) => source.serviceName == 'org.freedesktop.ScreenSaver',
        ),
        hasLength(2),
      );
      expect(
        sources.where((source) => source.serviceName == 'org.kde.screensaver'),
        hasLength(2),
      );
    });

    test('probes source definitions independently', () async {
      final probedLabels = <String>[];

      final availableSources =
          await LinuxDbusPowerEventAdapter.probeAvailableSources(
            sources: LinuxDbusPowerEventAdapter.knownSources,
            probeSource: (source) async {
              probedLabels.add(source.label);
              return source.serviceName == 'org.gnome.ScreenSaver';
            },
            requestTimeout: const Duration(seconds: 1),
          );

      expect(
        probedLabels,
        LinuxDbusPowerEventAdapter.knownSources
            .map((source) => source.label)
            .toList(),
      );
      expect(availableSources.single.serviceName, 'org.gnome.ScreenSaver');
    });

    test('logs missing optional D-Bus sources without error noise', () async {
      final logger = _CapturingDiagnosticLogger();
      final missingSource = _lockSource();
      final availableSource = _sleepSource();

      final availableSources =
          await LinuxDbusPowerEventAdapter.probeAvailableSources(
            sources: [missingSource, availableSource],
            probeSource: (source) async {
              if (source == missingSource) {
                throw DBusServiceUnknownException(
                  DBusMethodErrorResponse(
                    'org.freedesktop.DBus.Error.ServiceUnknown',
                    const [DBusString('service is not available')],
                  ),
                );
              }
              return true;
            },
            requestTimeout: const Duration(seconds: 1),
            logger: logger,
          );

      expect(availableSources, [availableSource]);
      expect(logger.errors, isEmpty);
      expect(logger.debugMessages, hasLength(1));
      expect(logger.debugMessages.single, contains('unavailable'));
      expect(logger.debugMessages.single, contains(missingSource.label));
    });

    test('logs unexpected source probe failures as errors', () async {
      final logger = _CapturingDiagnosticLogger();
      final source = _sleepSource();

      final availableSources =
          await LinuxDbusPowerEventAdapter.probeAvailableSources(
            sources: [source],
            probeSource: (_) async => throw StateError('probe exploded'),
            requestTimeout: const Duration(seconds: 1),
            logger: logger,
          );

      expect(availableSources, isEmpty);
      expect(logger.debugMessages, isEmpty);
      expect(logger.errors, hasLength(1));
      expect(
        logger.errors.single.message,
        'Linux power event source probe failed for ${source.label}',
      );
      expect(logger.errors.single.error, isA<StateError>());
    });

    test('matches introspection by interface, signal, and signature', () {
      final source = _lockSource();
      final introspection = DBusIntrospectNode(
        interfaces: [
          DBusIntrospectInterface(
            source.interfaceName,
            signals: [
              DBusIntrospectSignal(
                source.signalName,
                args: [
                  DBusIntrospectArgument(
                    DBusSignature.boolean,
                    DBusArgumentDirection.out,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      expect(
        LinuxDbusPowerEventAdapter.introspectionContainsSignal(
          introspection,
          source,
        ),
        isTrue,
      );
      expect(
        LinuxDbusPowerEventAdapter.introspectionContainsSignal(
          DBusIntrospectNode(),
          source,
        ),
        isFalse,
      );
    });

    test('malformed signal values are surfaced as errors', () {
      final source = _sleepSource();

      expect(
        () =>
            LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const []),
        throwsStateError,
      );
      expect(
        () => LinuxDbusPowerEventAdapter.eventFromSignalValues(source, const [
          DBusString('true'),
        ]),
        throwsStateError,
      );
    });

    test('merges available source streams and closes on cancel', () async {
      final sleepSource = _sleepSource();
      final lockSource = _lockSource();
      final controllers =
          <LinuxDbusPowerEventSource, StreamController<List<DBusValue>>>{};
      var closeRequests = 0;
      final closed = Completer<void>();
      final adapter = await LinuxDbusPowerEventAdapter.create(
        sources: [sleepSource, lockSource],
        probeSource: (_) async => true,
        signalValueStreamFactory: (source) {
          return controllers
              .putIfAbsent(
                source,
                () => StreamController<List<DBusValue>>.broadcast(),
              )
              .stream;
        },
        close: () async {
          closeRequests += 1;
          closed.complete();
        },
      );
      addTearDown(() async {
        for (final controller in controllers.values) {
          await controller.close();
        }
      });

      expect(adapter, isNotNull);
      expect(adapter!.sources, [sleepSource, lockSource]);

      final events = <PowerEvent>[];
      final subscription = adapter.events.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      controllers[sleepSource]!.add(const [DBusBoolean(true)]);
      controllers[lockSource]!.add(const [DBusBoolean(true)]);
      await Future<void>.delayed(Duration.zero);

      expect(events, [PowerEvent.sleep, PowerEvent.lock]);

      await subscription.cancel();
      await closed.future.timeout(const Duration(seconds: 1));
      expect(closeRequests, 1);
    });

    test('returns null when no sources are available', () async {
      var closeRequests = 0;

      final adapter = await LinuxDbusPowerEventAdapter.create(
        sources: [_sleepSource()],
        probeSource: (_) async => false,
        signalValueStreamFactory: (_) => const Stream.empty(),
        close: () async {
          closeRequests += 1;
        },
      );

      expect(adapter, isNull);
      expect(closeRequests, 1);
    });
  });
}

LinuxDbusPowerEventSource _sleepSource() {
  return LinuxDbusPowerEventAdapter.knownSources.singleWhere(
    (source) => source.signalKind == LinuxDbusPowerSignalKind.prepareForSleep,
  );
}

LinuxDbusPowerEventSource _lockSource() {
  return LinuxDbusPowerEventAdapter.knownSources.firstWhere(
    (source) => source.signalKind == LinuxDbusPowerSignalKind.activeChanged,
  );
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
