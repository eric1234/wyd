import 'package:flutter/services.dart';

import '../../application/application.dart';

final class EventChannelPowerEventAdapter implements PowerEventAdapter {
  const EventChannelPowerEventAdapter({
    EventChannel channel = const EventChannel('dev.wyd.tracker/power_events'),
  }) : _channel = channel;

  final EventChannel _channel;

  @override
  Stream<PowerEvent> get events {
    return _channel.receiveBroadcastStream().map(_decodePowerEvent);
  }

  PowerEvent _decodePowerEvent(Object? event) {
    return switch (event) {
      'lock' => PowerEvent.lock,
      'sleep' => PowerEvent.sleep,
      _ => throw ArgumentError.value(event, 'event', 'Unknown power event.'),
    };
  }
}
