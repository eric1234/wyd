import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../../application/application.dart';
import 'linux_dbus_power_event_adapter.dart';

typedef LinuxLogindInhibitorFactory = Future<LinuxLogindInhibitor> Function();
typedef LinuxLogindSignalValueStreamFactory =
    Stream<List<DBusValue>> Function(LinuxLogindSignal signal);

enum LinuxLogindSignalKind { prepareForSleep, prepareForShutdown }

final class LinuxLogindSignal {
  const LinuxLogindSignal({
    required this.label,
    required this.signalName,
    required this.kind,
  });

  final String label;
  final String signalName;
  final LinuxLogindSignalKind kind;
}

abstract interface class LinuxLogindInhibitor {
  Future<void> release();
}

final class LinuxLogindLifecyclePowerAdapter
    implements AcknowledgedPowerEventAdapter, DisposablePlatformAdapter {
  LinuxLogindLifecyclePowerAdapter._({
    required LinuxLogindInhibitorFactory acquireInhibitor,
    required LinuxLogindSignalValueStreamFactory logindSignalValueStreamFactory,
    required List<LinuxDbusPowerEventSource> lockSources,
    required LinuxDbusSignalValueStreamFactory lockSignalValueStreamFactory,
    required DateTime Function() nowUtc,
    required Duration requestTimeout,
    required Future<void> Function() close,
    required DiagnosticLogger logger,
  }) : _acquireInhibitor = acquireInhibitor,
       _logindSignalValueStreamFactory = logindSignalValueStreamFactory,
       _lockSources = List.unmodifiable(lockSources),
       _lockSignalValueStreamFactory = lockSignalValueStreamFactory,
       _nowUtc = nowUtc,
       _requestTimeout = requestTimeout,
       _close = close,
       _logger = logger;

  static const defaultRequestTimeout = Duration(seconds: 3);

  static const logindSignals = <LinuxLogindSignal>[
    LinuxLogindSignal(
      label: 'systemd-logind sleep',
      signalName: 'PrepareForSleep',
      kind: LinuxLogindSignalKind.prepareForSleep,
    ),
    LinuxLogindSignal(
      label: 'systemd-logind shutdown',
      signalName: 'PrepareForShutdown',
      kind: LinuxLogindSignalKind.prepareForShutdown,
    ),
  ];

  static Future<LinuxLogindLifecyclePowerAdapter?> create({
    DBusClient Function()? systemClientFactory,
    DBusClient Function()? sessionClientFactory,
    LinuxLogindInhibitorFactory? acquireInhibitor,
    LinuxLogindSignalValueStreamFactory? logindSignalValueStreamFactory,
    LinuxDbusPowerEventSourceProbe? probeLockSource,
    LinuxDbusSignalValueStreamFactory? lockSignalValueStreamFactory,
    Future<void> Function()? close,
    Iterable<LinuxDbusPowerEventSource> lockSources =
        LinuxDbusPowerEventAdapter.knownSources,
    DateTime Function()? nowUtc,
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
      try {
        await close?.call();
      } catch (error, stackTrace) {
        logger.error(
          'Linux logind adapter close hook failed',
          error,
          stackTrace,
        );
      }
      await _closeIgnoringErrors(systemClient);
      await _closeIgnoringErrors(sessionClient);
    }

    try {
      final acquire =
          acquireInhibitor ??
          () => _acquireDbusInhibitor(clientFor(LinuxDbusBus.system));
      final lockSourceCandidates = lockSources.where(
        (source) => source.isLockSource,
      );
      final availableLockSources =
          await LinuxDbusPowerEventAdapter.probeAvailableSources(
            sources: lockSourceCandidates,
            probeSource:
                probeLockSource ??
                (source) => _probeDbusSource(clientFor(source.bus), source),
            requestTimeout: requestTimeout,
            logger: logger,
          );

      logger.debug(
        'Linux logind adapter available; lock sources: '
        '${availableLockSources.isEmpty ? 'none detected' : availableLockSources.map((source) => source.label).join(', ')}',
      );

      final adapter = LinuxLogindLifecyclePowerAdapter._(
        acquireInhibitor: acquire,
        logindSignalValueStreamFactory:
            logindSignalValueStreamFactory ??
            (signal) =>
                _logindSignalValuesFor(clientFor(LinuxDbusBus.system), signal),
        lockSources: availableLockSources,
        lockSignalValueStreamFactory:
            lockSignalValueStreamFactory ??
            (source) => _lockSignalValuesFor(clientFor(source.bus), source),
        nowUtc: nowUtc ?? () => DateTime.now().toUtc(),
        requestTimeout: requestTimeout,
        close: closeClients,
        logger: logger,
      );
      return adapter;
    } catch (error, stackTrace) {
      logger.error(
        'Linux logind lifecycle/power adapter creation failed',
        error,
        stackTrace,
      );
      await closeClients();
      return null;
    }
  }

  final LinuxLogindInhibitorFactory _acquireInhibitor;
  final LinuxLogindSignalValueStreamFactory _logindSignalValueStreamFactory;
  final List<LinuxDbusPowerEventSource> _lockSources;
  final LinuxDbusSignalValueStreamFactory _lockSignalValueStreamFactory;
  final DateTime Function() _nowUtc;
  final Duration _requestTimeout;
  final Future<void> Function() _close;
  final DiagnosticLogger _logger;

  final List<StreamSubscription<List<DBusValue>>> _subscriptions = [];
  LinuxLogindInhibitor? _inhibitor;
  Future<void> Function(PowerEventOccurrence occurrence)? _onPowerEvent;
  Future<void> _eventChain = Future.value();
  bool _started = false;
  bool _disposed = false;

  @override
  Stream<PowerEvent> get events => const Stream.empty();

  @override
  Future<void> initializeAcknowledged(
    Future<void> Function(PowerEventOccurrence occurrence) onPowerEvent,
  ) async {
    _onPowerEvent = onPowerEvent;
    await _startIfReady();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _eventChain;
    await _releaseInhibitor();
    await _close();
  }

  Future<void> _startIfReady() async {
    if (_started || _disposed || _onPowerEvent == null) {
      return;
    }
    _started = true;

    for (final signal in logindSignals) {
      final subscription = _logindSignalValueStreamFactory(signal).listen(
        (values) => _enqueue(() => _handleLogindSignal(signal, values)),
        onError: _logSignalStreamError,
      );
      _subscriptions.add(subscription);
    }

    for (final source in _lockSources) {
      final subscription = _lockSignalValueStreamFactory(source).listen(
        (values) => _enqueue(() => _handleLockSignal(source, values)),
        onError: _logSignalStreamError,
      );
      _subscriptions.add(subscription);
    }

    await _acquireInhibitorIfNeeded();
  }

  void _enqueue(Future<void> Function() action) {
    _eventChain = _eventChain.then((_) async {
      if (_disposed) {
        return;
      }
      try {
        await action();
      } catch (error, stackTrace) {
        _logger.error('Linux logind event handling failed', error, stackTrace);
      }
    });
  }

  Future<void> _handleLogindSignal(
    LinuxLogindSignal signal,
    List<DBusValue> values,
  ) async {
    final started = _singleBooleanValue(signal.label, values);
    if (!started) {
      await _acquireInhibitorIfNeeded();
      return;
    }

    switch (signal.kind) {
      case LinuxLogindSignalKind.prepareForSleep:
        await _handleSleepStarted();
      case LinuxLogindSignalKind.prepareForShutdown:
        await _handleShutdownStarted();
    }
  }

  Future<void> _handleLockSignal(
    LinuxDbusPowerEventSource source,
    List<DBusValue> values,
  ) async {
    final locked = _singleBooleanValue(source.label, values);
    if (!locked) {
      return;
    }
    await _onPowerEvent?.call(
      PowerEventOccurrence(event: PowerEvent.lock, occurredAtUtc: _nowUtc()),
    );
  }

  Future<void> _handleSleepStarted() async {
    final occurredAtUtc = _nowUtc();
    try {
      await _onPowerEvent?.call(
        PowerEventOccurrence(
          event: PowerEvent.sleep,
          occurredAtUtc: occurredAtUtc,
        ),
      );
    } finally {
      await _releaseInhibitor();
    }
  }

  Future<void> _handleShutdownStarted() async {
    final occurredAtUtc = _nowUtc();
    try {
      await _onPowerEvent?.call(
        PowerEventOccurrence(
          event: PowerEvent.shutdown,
          occurredAtUtc: occurredAtUtc,
        ),
      );
    } finally {
      await _releaseInhibitor();
    }
  }

  Future<void> _acquireInhibitorIfNeeded() async {
    if (_disposed || _inhibitor != null) {
      return;
    }
    late final Future<LinuxLogindInhibitor> acquireFuture;
    try {
      acquireFuture = _acquireInhibitor();
    } catch (error, stackTrace) {
      _logger.error(
        'Linux logind inhibitor acquisition failed',
        error,
        stackTrace,
      );
      return;
    }

    LinuxLogindInhibitor inhibitor;
    try {
      inhibitor = await acquireFuture.timeout(_requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _logger.error(
        'Linux logind inhibitor acquisition timed out',
        error,
        stackTrace,
      );
      _releaseLateInhibitor(
        acquireFuture,
        logger: _logger,
        failureMessage:
            'Linux logind inhibitor acquisition failed after timeout',
      );
      return;
    } catch (error, stackTrace) {
      _logger.error(
        'Linux logind inhibitor acquisition failed',
        error,
        stackTrace,
      );
      return;
    }

    if (_disposed || _inhibitor != null) {
      await _releaseIgnoringErrors(inhibitor);
      return;
    }
    _inhibitor = inhibitor;
  }

  static void _releaseLateInhibitor(
    Future<LinuxLogindInhibitor> acquireFuture, {
    required DiagnosticLogger logger,
    required String failureMessage,
  }) {
    unawaited(
      acquireFuture.then(
        _releaseIgnoringErrors,
        onError: (Object error, StackTrace stackTrace) {
          logger.error(failureMessage, error, stackTrace);
        },
      ),
    );
  }

  Future<void> _releaseInhibitor() async {
    final inhibitor = _inhibitor;
    if (inhibitor == null) {
      return;
    }
    _inhibitor = null;
    await inhibitor.release();
  }

  void _logSignalStreamError(Object error, StackTrace stackTrace) {
    _logger.error('Linux logind signal stream failed', error, stackTrace);
  }

  static Future<LinuxLogindInhibitor> _acquireDbusInhibitor(
    DBusClient client,
  ) async {
    final object = DBusRemoteObject(
      client,
      name: _logindServiceName,
      path: _logindObjectPath,
    );
    final result = await object
        .callMethod(_logindManagerInterface, 'Inhibit', const [
          DBusString('sleep:shutdown'),
          DBusString('wyd'),
          DBusString('Record current task before sleep or shutdown'),
          DBusString('delay'),
        ], replySignature: DBusSignature.unixFd);
    return _FileLinuxLogindInhibitor(result.returnValues.single.asUnixFd());
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
    return LinuxDbusPowerEventAdapter.introspectionContainsSignal(
      introspection,
      source,
    );
  }

  static Stream<List<DBusValue>> _logindSignalValuesFor(
    DBusClient client,
    LinuxLogindSignal signal,
  ) {
    final object = DBusRemoteObject(
      client,
      name: _logindServiceName,
      path: _logindObjectPath,
    );
    return DBusRemoteObjectSignalStream(
      object: object,
      interface: _logindManagerInterface,
      name: signal.signalName,
      signature: DBusSignature.boolean,
    ).map((signal) => signal.values);
  }

  static Stream<List<DBusValue>> _lockSignalValuesFor(
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

  static bool _singleBooleanValue(String label, List<DBusValue> values) {
    if (values.length != 1 ||
        values.single.signature != DBusSignature.boolean) {
      throw StateError(
        '$label emitted ${values.map((value) => value.signature.value).join()} values, expected b.',
      );
    }
    return values.single.asBoolean();
  }

  static Future<void> _releaseIgnoringErrors(
    LinuxLogindInhibitor? inhibitor,
  ) async {
    if (inhibitor == null) {
      return;
    }
    try {
      await inhibitor.release();
    } catch (_) {}
  }

  static Future<void> _closeIgnoringErrors(DBusClient? client) async {
    if (client == null) {
      return;
    }
    try {
      await client.close();
    } catch (_) {}
  }

  static const _logindServiceName = 'org.freedesktop.login1';
  static const _logindManagerInterface = 'org.freedesktop.login1.Manager';
  static final _logindObjectPath = DBusObjectPath.unchecked(
    '/org/freedesktop/login1',
  );
}

final class _FileLinuxLogindInhibitor implements LinuxLogindInhibitor {
  _FileLinuxLogindInhibitor(ResourceHandle handle) : _file = handle.toFile();

  RandomAccessFile? _file;

  @override
  Future<void> release() async {
    final file = _file;
    if (file == null) {
      return;
    }
    _file = null;
    await file.close();
  }
}
