import 'package:dbus/dbus.dart';

import '../../application/application.dart';

typedef ScreenSaverIdleDurationReader = Future<Duration?> Function();

final class ScreenSaverIdleSource {
  const ScreenSaverIdleSource({
    required this.label,
    required this.serviceName,
    required this.objectPath,
    required this.interfaceName,
  });

  final String label;
  final String serviceName;
  final DBusObjectPath objectPath;
  final String interfaceName;
}

final class ScreenSaverIdleUserIdleDetector implements UserIdleDetector {
  const ScreenSaverIdleUserIdleDetector._({
    required ScreenSaverIdleDurationReader getIdleDuration,
    required Duration requestTimeout,
    required String sourceLabel,
    required DiagnosticLogger logger,
  }) : _getIdleDuration = getIdleDuration,
       _requestTimeout = requestTimeout,
       _sourceLabel = sourceLabel,
       _logger = logger;

  static const defaultRequestTimeout = Duration(seconds: 3);
  static const knownSources = <ScreenSaverIdleSource>[
    ScreenSaverIdleSource(
      label: 'freedesktop screensaver idle (/ScreenSaver)',
      serviceName: 'org.freedesktop.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/ScreenSaver'),
      interfaceName: 'org.freedesktop.ScreenSaver',
    ),
    ScreenSaverIdleSource(
      label: 'freedesktop screensaver idle (/org/freedesktop/ScreenSaver)',
      serviceName: 'org.freedesktop.ScreenSaver',
      objectPath: DBusObjectPath.unchecked('/org/freedesktop/ScreenSaver'),
      interfaceName: 'org.freedesktop.ScreenSaver',
    ),
  ];

  final ScreenSaverIdleDurationReader _getIdleDuration;
  final Duration _requestTimeout;
  final String _sourceLabel;
  final DiagnosticLogger _logger;

  static Future<ScreenSaverIdleUserIdleDetector?> create({
    ScreenSaverIdleDurationReader? getIdleDuration,
    DBusClient Function()? sessionClientFactory,
    Iterable<ScreenSaverIdleSource> sources = knownSources,
    Duration requestTimeout = defaultRequestTimeout,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    if (getIdleDuration != null) {
      return _createFromReader(
        getIdleDuration,
        sourceLabel: 'injected reader',
        requestTimeout: requestTimeout,
        logger: logger,
      );
    }

    DBusClient? client;
    try {
      client =
          sessionClientFactory?.call() ??
          DBusClient.session(introspectable: false);
      for (final source in sources) {
        final object = DBusRemoteObject(
          client,
          name: source.serviceName,
          path: source.objectPath,
        );
        final detector = await _createFromReader(
          () => _getDbusIdleDuration(object, source, logger: logger),
          sourceLabel: source.label,
          requestTimeout: requestTimeout,
          logger: logger,
        );
        if (detector != null) {
          return detector;
        }
      }

      logger.debug('ScreenSaver idle detector unavailable');
      await _closeIgnoringErrors(client);
      return null;
    } catch (error, stackTrace) {
      logger.error(
        'ScreenSaver idle detector creation failed',
        error,
        stackTrace,
      );
      if (client != null) {
        await _closeIgnoringErrors(client);
      }
      return null;
    }
  }

  static Future<ScreenSaverIdleUserIdleDetector?> _createFromReader(
    ScreenSaverIdleDurationReader getIdleDuration, {
    required String sourceLabel,
    required Duration requestTimeout,
    required DiagnosticLogger logger,
  }) async {
    try {
      final idleDuration = await getIdleDuration().timeout(requestTimeout);
      if (idleDuration == null) {
        logger.debug(
          'ScreenSaver idle detector probe returned no idle duration for $sourceLabel',
        );
        return null;
      }
      logger.debug(
        'ScreenSaver idle detector available via $sourceLabel, current idle duration ${_formatDuration(idleDuration)}',
      );
      return ScreenSaverIdleUserIdleDetector._(
        getIdleDuration: getIdleDuration,
        requestTimeout: requestTimeout,
        sourceLabel: sourceLabel,
        logger: logger,
      );
    } catch (error, stackTrace) {
      logger.error(
        'ScreenSaver idle detector probe failed for $sourceLabel',
        error,
        stackTrace,
      );
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
        _logger.debug(
          'ScreenSaver idle check via $_sourceLabel: idle=${_formatDuration(idleDuration)}, minimum=${_formatDuration(minimumIdleDuration)}, deferral=none',
        );
        return null;
      }

      final deferral = minimumIdleDuration - idleDuration;
      _logger.debug(
        'ScreenSaver idle check via $_sourceLabel: idle=${_formatDuration(idleDuration)}, minimum=${_formatDuration(minimumIdleDuration)}, deferral=${_formatDuration(deferral)}',
      );
      return deferral;
    } catch (error, stackTrace) {
      _logger.error(
        'ScreenSaver idle check failed via $_sourceLabel',
        error,
        stackTrace,
      );
      return null;
    }
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null) {
      return 'unavailable';
    }
    return '${duration.inMilliseconds}ms';
  }

  static Future<Duration?> _getDbusIdleDuration(
    DBusRemoteObject object,
    ScreenSaverIdleSource source, {
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) async {
    final response = await object.callMethod(
      source.interfaceName,
      'GetSessionIdleTime',
      const [],
    );
    logger.debug(
      'ScreenSaver idle raw response via ${source.label}: ${_formatDbusValues(response.returnValues)}',
    );
    return idleDurationFromDbusReturnValues(response.returnValues);
  }

  static String _formatDbusValues(List<DBusValue> values) {
    if (values.isEmpty) {
      return '[]';
    }
    return values.map(_formatDbusValue).join(', ');
  }

  static String _formatDbusValue(DBusValue value) {
    final signature = value.signature.value;
    if (signature == 'v') {
      return 'v(${_formatDbusValue(value.asVariant())})';
    }
    if (signature.startsWith('(')) {
      return '$signature(${value.asStruct().map(_formatDbusValue).join(', ')})';
    }

    final rawValue = switch (signature) {
      't' => value.asUint64(),
      'u' => value.asUint32(),
      'x' => value.asInt64(),
      'i' => value.asInt32(),
      _ => null,
    };
    if (rawValue == null) {
      return signature;
    }
    return '$signature=$rawValue';
  }

  static Duration? idleDurationFromDbusReturnValues(
    List<DBusValue> returnValues,
  ) {
    if (returnValues.length != 1) {
      throw StateError(
        'ScreenSaver idle monitor returned an unexpected response.',
      );
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
          'ScreenSaver idle monitor returned a tuple with ${children.length} values, expected one.',
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
        'ScreenSaver idle monitor returned ${unwrappedValue.signature.value}, expected an integer.',
      ),
    };
  }

  static Future<void> _closeIgnoringErrors(DBusClient client) async {
    try {
      await client.close();
    } catch (_) {}
  }
}
