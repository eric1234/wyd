import 'package:flutter/services.dart';

import '../../application/application.dart';

final class MethodChannelAcknowledgedPowerEventAdapter
    implements AcknowledgedPowerEventAdapter {
  const MethodChannelAcknowledgedPowerEventAdapter({
    MethodChannel channel = const MethodChannel(
      'dev.wyd.tracker/power_events_ack',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Stream<PowerEvent> get events => const Stream.empty();

  @override
  Future<void> initializeAcknowledged(
    Future<void> Function(PowerEventOccurrence occurrence) onPowerEvent,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'powerEvent') {
        throw MissingPluginException('No handler for ${call.method}');
      }

      await onPowerEvent(_decodeOccurrence(call.arguments));
    });

    try {
      await _channel.invokeMethod<void>('powerEventsReady');
    } on MissingPluginException {
      // Tests and older native runners may not expose this channel yet.
    }
  }

  PowerEventOccurrence _decodeOccurrence(Object? arguments) {
    if (arguments is! Map<Object?, Object?>) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'Expected a power event argument map.',
      );
    }

    final event = arguments['event'];
    if (event is! String) {
      throw ArgumentError.value(event, 'event', 'Expected a power event name.');
    }

    final occurredAtUtc = arguments['occurredAtUtc'];
    if (occurredAtUtc is! String) {
      throw ArgumentError.value(
        occurredAtUtc,
        'occurredAtUtc',
        'Expected an ISO-8601 timestamp.',
      );
    }

    return PowerEventOccurrence(
      event: _decodePowerEvent(event),
      occurredAtUtc: DateTime.parse(occurredAtUtc).toUtc(),
    );
  }

  PowerEvent _decodePowerEvent(String event) {
    return switch (event) {
      'lock' => PowerEvent.lock,
      'sleep' => PowerEvent.sleep,
      'shutdown' => PowerEvent.shutdown,
      'shutdown_cancelled' => PowerEvent.shutdownCancelled,
      _ => throw ArgumentError.value(event, 'event', 'Unknown power event.'),
    };
  }
}
