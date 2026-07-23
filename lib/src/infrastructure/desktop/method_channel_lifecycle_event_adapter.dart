import 'package:flutter/services.dart';

import '../../application/application.dart';

final class MethodChannelLifecycleEventAdapter
    implements LifecycleEventAdapter {
  const MethodChannelLifecycleEventAdapter({
    MethodChannel channel = const MethodChannel(
      'dev.wyd.tracker/lifecycle_events',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> initialize(
    Future<void> Function(LifecycleEventOccurrence occurrence) onEvent,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'lifecycleEvent') {
        throw MissingPluginException('No handler for ${call.method}');
      }
      await onEvent(_decodeOccurrence(call.arguments));
    });
    try {
      await _channel.invokeMethod<void>('lifecycleEventsReady');
    } on MissingPluginException {
      // Unsupported native runners expose no lifecycle events.
    }
  }

  LifecycleEventOccurrence _decodeOccurrence(Object? arguments) {
    if (arguments is! Map<Object?, Object?>) {
      throw ArgumentError.value(arguments, 'arguments', 'Expected a map.');
    }
    final kind = arguments['kind'];
    final occurredAtUtc = arguments['occurredAtUtc'];
    if (kind is! String || occurredAtUtc is! String) {
      throw ArgumentError.value(arguments, 'arguments', 'Invalid event data.');
    }
    return LifecycleEventOccurrence(
      kind: switch (kind) {
        'lock' => LifecycleEventKind.lock,
        'sleep' => LifecycleEventKind.sleep,
        'shutdown' => LifecycleEventKind.shutdown,
        'shutdown_cancelled' => LifecycleEventKind.shutdownCancelled,
        'termination' => LifecycleEventKind.termination,
        _ => throw ArgumentError.value(kind, 'kind', 'Unknown lifecycle kind.'),
      },
      occurredAtUtc: DateTime.parse(occurredAtUtc).toUtc(),
    );
  }
}
