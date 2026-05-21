import 'package:dbus/dbus.dart';

import '../../application/application.dart';

typedef GnomeIdleDurationReader = Future<Duration?> Function();

final class GnomeIdleUserIdleDetector implements UserIdleDetector {
  const GnomeIdleUserIdleDetector._({
    required GnomeIdleDurationReader getIdleDuration,
    required Duration requestTimeout,
  }) : _getIdleDuration = getIdleDuration,
       _requestTimeout = requestTimeout;

  static const defaultRequestTimeout = Duration(seconds: 3);
  static const _busName = 'org.gnome.Mutter.IdleMonitor';
  static const _objectPath = DBusObjectPath.unchecked(
    '/org/gnome/Mutter/IdleMonitor/Core',
  );
  static const _interfaceName = 'org.gnome.Mutter.IdleMonitor';

  final GnomeIdleDurationReader _getIdleDuration;
  final Duration _requestTimeout;

  static Future<GnomeIdleUserIdleDetector?> create({
    GnomeIdleDurationReader? getIdleDuration,
    Duration requestTimeout = defaultRequestTimeout,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    if (getIdleDuration != null) {
      return _createFromReader(
        getIdleDuration,
        requestTimeout: requestTimeout,
        logger: logger,
      );
    }

    DBusClient? client;
    try {
      client = DBusClient.session(introspectable: false);
      final object = DBusRemoteObject(
        client,
        name: _busName,
        path: _objectPath,
      );
      final detector = await _createFromReader(
        () => _getDbusIdleDuration(object),
        requestTimeout: requestTimeout,
        logger: logger,
      );
      if (detector == null) {
        await _closeIgnoringErrors(client);
      }
      return detector;
    } catch (error, stackTrace) {
      logger.error('GNOME idle detector creation failed', error, stackTrace);
      if (client != null) {
        await _closeIgnoringErrors(client);
      }
      return null;
    }
  }

  static Future<GnomeIdleUserIdleDetector?> _createFromReader(
    GnomeIdleDurationReader getIdleDuration, {
    required Duration requestTimeout,
    required DiagnosticLogger logger,
  }) async {
    try {
      final idleDuration = await getIdleDuration().timeout(requestTimeout);
      if (idleDuration == null) {
        logger.debug('GNOME idle detector probe returned no idle duration');
        return null;
      }
      logger.debug(
        'GNOME idle detector available, current idle duration ${idleDuration.inMilliseconds}ms',
      );
      return GnomeIdleUserIdleDetector._(
        getIdleDuration: getIdleDuration,
        requestTimeout: requestTimeout,
      );
    } catch (error, stackTrace) {
      logger.error('GNOME idle detector probe failed', error, stackTrace);
      return null;
    }
  }

  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) async {
    if (minimumIdleDuration <= Duration.zero) {
      return null;
    }

    try {
      final idleDuration = await _getIdleDuration().timeout(_requestTimeout);
      if (idleDuration == null || idleDuration >= minimumIdleDuration) {
        return null;
      }

      return minimumIdleDuration - idleDuration;
    } catch (_) {
      return null;
    }
  }

  static Future<Duration?> _getDbusIdleDuration(DBusRemoteObject object) async {
    final response = await object.callMethod(
      _interfaceName,
      'GetIdletime',
      const [],
    );
    return idleDurationFromDbusReturnValues(response.returnValues);
  }

  static Duration? idleDurationFromDbusReturnValues(
    List<DBusValue> returnValues,
  ) {
    if (returnValues.length != 1) {
      throw StateError('GNOME idle monitor returned an unexpected response.');
    }
    final milliseconds = _millisecondsFromValue(returnValues.single);
    if (milliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: milliseconds);
  }

  static int _millisecondsFromValue(DBusValue value) {
    final unwrappedValue = value.signature.value == 'v'
        ? value.asVariant()
        : value;
    if (unwrappedValue.signature.value.startsWith('(')) {
      final children = unwrappedValue.asStruct();
      if (children.length != 1) {
        throw StateError(
          'GNOME idle monitor returned a tuple with ${children.length} values, expected one.',
        );
      }
      return _millisecondsFromValue(children.single);
    }

    return switch (unwrappedValue.signature.value) {
      't' => unwrappedValue.asUint64(),
      'u' => unwrappedValue.asUint32(),
      'x' => unwrappedValue.asInt64(),
      'i' => unwrappedValue.asInt32(),
      _ => throw StateError(
        'GNOME idle monitor returned ${unwrappedValue.signature.value}, expected an integer.',
      ),
    };
  }

  static Future<void> _closeIgnoringErrors(DBusClient client) async {
    try {
      await client.close();
    } catch (_) {}
  }
}
