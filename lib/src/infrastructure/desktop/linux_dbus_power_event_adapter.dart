import 'dart:async';

import 'package:dbus/dbus.dart';

import '../../application/application.dart';

typedef LinuxDbusPowerEventSourceProbe =
    Future<bool> Function(LinuxDbusPowerEventSource source);
typedef LinuxDbusSignalValueStreamFactory =
    Stream<List<DBusValue>> Function(LinuxDbusPowerEventSource source);

enum LinuxDbusBus { system, session }

enum LinuxDbusPowerSignalKind { prepareForSleep, activeChanged }

final class LinuxDbusPowerEventSource {
  const LinuxDbusPowerEventSource({
    required this.label,
    required this.bus,
    required this.serviceName,
    required this.objectPath,
    required this.interfaceName,
    required this.signalName,
    required this.signalKind,
    this.signature = DBusSignature.boolean,
  });

  final String label;
  final LinuxDbusBus bus;
  final String serviceName;
  final DBusObjectPath objectPath;
  final String interfaceName;
  final String signalName;
  final LinuxDbusPowerSignalKind signalKind;
  final DBusSignature signature;

  bool get isSleepSource =>
      signalKind == LinuxDbusPowerSignalKind.prepareForSleep;
  bool get isLockSource => signalKind == LinuxDbusPowerSignalKind.activeChanged;
}

final class LinuxDbusPowerEventAdapter implements PowerEventAdapter {
  LinuxDbusPowerEventAdapter._({
    required List<LinuxDbusPowerEventSource> sources,
    required LinuxDbusSignalValueStreamFactory signalValueStreamFactory,
    required Future<void> Function() close,
  }) : _sources = List.unmodifiable(sources),
       _signalValueStreamFactory = signalValueStreamFactory,
       _close = close;

  static const defaultRequestTimeout = Duration(seconds: 3);

  static const knownSources = <LinuxDbusPowerEventSource>[
    LinuxDbusPowerEventSource(
      label: 'systemd-logind sleep',
      bus: LinuxDbusBus.system,
      serviceName: 'org.freedesktop.login1',
      objectPath: DBusObjectPath.unchecked('/org/freedesktop/login1'),
      interfaceName: 'org.freedesktop.login1.Manager',
      signalName: 'PrepareForSleep',
      signalKind: LinuxDbusPowerSignalKind.prepareForSleep,
    ),
    LinuxDbusPowerEventSource(
      label: 'Cinnamon screensaver lock',
      bus: LinuxDbusBus.session,
      serviceName: 'org.cinnamon.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/org/cinnamon/ScreenSaver'),
      interfaceName: 'org.cinnamon.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'GNOME screensaver lock',
      bus: LinuxDbusBus.session,
      serviceName: 'org.gnome.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/org/gnome/ScreenSaver'),
      interfaceName: 'org.gnome.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'Xfce screensaver lock',
      bus: LinuxDbusBus.session,
      serviceName: 'org.xfce.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/org/xfce/ScreenSaver'),
      interfaceName: 'org.xfce.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'freedesktop screensaver lock (/ScreenSaver)',
      bus: LinuxDbusBus.session,
      serviceName: 'org.freedesktop.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/ScreenSaver'),
      interfaceName: 'org.freedesktop.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'freedesktop screensaver lock (/org/freedesktop/ScreenSaver)',
      bus: LinuxDbusBus.session,
      serviceName: 'org.freedesktop.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/org/freedesktop/ScreenSaver'),
      interfaceName: 'org.freedesktop.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'KDE screensaver lock (/ScreenSaver)',
      bus: LinuxDbusBus.session,
      serviceName: 'org.kde.screensaver',
      objectPath: DBusObjectPath.unchecked('/ScreenSaver'),
      interfaceName: 'org.freedesktop.ScreenSaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
    LinuxDbusPowerEventSource(
      label: 'KDE screensaver lock (/org/kde/screensaver)',
      bus: LinuxDbusBus.session,
      serviceName: 'org.kde.screensaver',
      objectPath: DBusObjectPath.unchecked('/org/kde/screensaver'),
      interfaceName: 'org.kde.screensaver',
      signalName: 'ActiveChanged',
      signalKind: LinuxDbusPowerSignalKind.activeChanged,
    ),
  ];

  final List<LinuxDbusPowerEventSource> _sources;
  final LinuxDbusSignalValueStreamFactory _signalValueStreamFactory;
  final Future<void> Function() _close;

  List<LinuxDbusPowerEventSource> get sources => _sources;

  static Future<LinuxDbusPowerEventAdapter?> create({
    DBusClient Function()? systemClientFactory,
    DBusClient Function()? sessionClientFactory,
    LinuxDbusPowerEventSourceProbe? probeSource,
    LinuxDbusSignalValueStreamFactory? signalValueStreamFactory,
    Future<void> Function()? close,
    Iterable<LinuxDbusPowerEventSource> sources = knownSources,
    Duration requestTimeout = defaultRequestTimeout,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    DBusClient? systemClient;
    DBusClient? sessionClient;

    DBusClient clientFor(LinuxDbusBus bus) {
      return switch (bus) {
        LinuxDbusBus.system =>
          systemClient ??=
              systemClientFactory?.call() ??
              DBusClient.system(introspectable: false),
        LinuxDbusBus.session =>
          sessionClient ??=
              sessionClientFactory?.call() ??
              DBusClient.session(introspectable: false),
      };
    }

    Future<void> closeClients() async {
      await close?.call();
      await _closeIgnoringErrors(systemClient);
      await _closeIgnoringErrors(sessionClient);
    }

    try {
      final availableSources = await probeAvailableSources(
        sources: sources,
        probeSource:
            probeSource ??
            (source) => _probeDbusSource(clientFor(source.bus), source),
        requestTimeout: requestTimeout,
        logger: logger,
      );

      if (availableSources.isEmpty) {
        logger.debug('Linux power event sources: none detected');
        await closeClients();
        return null;
      }

      final hasSleepSupport = availableSources.any(
        (source) => source.isSleepSource,
      );
      final hasLockSupport = availableSources.any(
        (source) => source.isLockSource,
      );
      logger.debug(
        'Linux power event sources: ${availableSources.map((source) => source.label).join(', ')}; '
        'sleep=${hasSleepSupport ? 'supported' : 'unsupported'}, '
        'lock=${hasLockSupport ? 'supported' : 'unsupported'}',
      );

      return LinuxDbusPowerEventAdapter._(
        sources: availableSources,
        signalValueStreamFactory:
            signalValueStreamFactory ??
            (source) => _signalValuesForSource(clientFor(source.bus), source),
        close: closeClients,
      );
    } catch (error, stackTrace) {
      logger.error(
        'Linux power event adapter creation failed',
        error,
        stackTrace,
      );
      await closeClients();
      return null;
    }
  }

  static Future<List<LinuxDbusPowerEventSource>> probeAvailableSources({
    required Iterable<LinuxDbusPowerEventSource> sources,
    required LinuxDbusPowerEventSourceProbe probeSource,
    required Duration requestTimeout,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    final probes = sources.map((source) async {
      try {
        final isAvailable = await probeSource(source).timeout(requestTimeout);
        if (isAvailable) {
          return source;
        }
      } catch (error, stackTrace) {
        if (_isUnavailableDbusProbeError(error)) {
          logger.debug(
            'Linux power event source unavailable for ${source.label}: $error',
          );
        } else {
          logger.error(
            'Linux power event source probe failed for ${source.label}',
            error,
            stackTrace,
          );
        }
      }
      return null;
    });
    final results = await Future.wait(probes);
    return results.whereType<LinuxDbusPowerEventSource>().toList();
  }

  static PowerEvent? eventFromSignalValues(
    LinuxDbusPowerEventSource source,
    List<DBusValue> values,
  ) {
    final isAway = _singleBooleanValue(source, values);
    if (!isAway) {
      return null;
    }

    return switch (source.signalKind) {
      LinuxDbusPowerSignalKind.prepareForSleep => PowerEvent.sleep,
      LinuxDbusPowerSignalKind.activeChanged => PowerEvent.lock,
    };
  }

  static bool introspectionContainsSignal(
    DBusIntrospectNode introspection,
    LinuxDbusPowerEventSource source,
  ) {
    return introspection.interfaces.any((interface) {
      if (interface.name != source.interfaceName) {
        return false;
      }
      return interface.signals.any(
        (signal) =>
            signal.name == source.signalName &&
            signal.signature == source.signature,
      );
    });
  }

  @override
  Stream<PowerEvent> get events {
    late final StreamController<PowerEvent> controller;
    final subscriptions = <StreamSubscription<List<DBusValue>>>[];

    controller = StreamController<PowerEvent>.broadcast(
      onListen: () {
        for (final source in _sources) {
          final subscription = _signalValueStreamFactory(source).listen((
            values,
          ) {
            try {
              final event = eventFromSignalValues(source, values);
              if (event != null) {
                controller.add(event);
              }
            } catch (error, stackTrace) {
              controller.addError(error, stackTrace);
            }
          }, onError: controller.addError);
          subscriptions.add(subscription);
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
        await _close();
      },
    );
    return controller.stream;
  }

  static Future<bool> _probeDbusSource(
    DBusClient client,
    LinuxDbusPowerEventSource source,
  ) async {
    final object = DBusRemoteObject(
      client,
      name: source.serviceName,
      path: source.objectPath,
    );
    final introspection = await object.introspect();
    return introspectionContainsSignal(introspection, source);
  }

  static bool _isUnavailableDbusProbeError(Object error) {
    return error is DBusServiceUnknownException ||
        error is DBusUnknownObjectException ||
        error is DBusUnknownInterfaceException;
  }

  static Stream<List<DBusValue>> _signalValuesForSource(
    DBusClient client,
    LinuxDbusPowerEventSource source,
  ) {
    final object = DBusRemoteObject(
      client,
      name: source.serviceName,
      path: source.objectPath,
    );
    return DBusRemoteObjectSignalStream(
      object: object,
      interface: source.interfaceName,
      name: source.signalName,
      signature: source.signature,
    ).map((signal) => signal.values);
  }

  static bool _singleBooleanValue(
    LinuxDbusPowerEventSource source,
    List<DBusValue> values,
  ) {
    if (values.length != 1 ||
        values.single.signature != DBusSignature.boolean) {
      throw StateError(
        '${source.label} emitted ${values.map((value) => value.signature.value).join()} values, expected b.',
      );
    }
    return values.single.asBoolean();
  }

  static Future<void> _closeIgnoringErrors(DBusClient? client) async {
    if (client == null) {
      return;
    }
    try {
      await client.close();
    } catch (_) {}
  }
}
