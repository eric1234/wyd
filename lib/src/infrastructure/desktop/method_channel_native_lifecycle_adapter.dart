import 'package:flutter/services.dart';

import '../../application/application.dart';

final class MethodChannelNativeLifecycleAdapter
    implements NativeLifecycleAdapter {
  MethodChannelNativeLifecycleAdapter({
    MethodChannel channel = const MethodChannel('dev.wyd.tracker/lifecycle'),
  }) : _channel = channel;

  final MethodChannel _channel;
  Future<void>? _terminationPreparation;

  @override
  Future<void> initialize(
    Future<void> Function(NativeTerminationOccurrence occurrence)
    onTerminationRequested,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'prepareForTermination') {
        throw MissingPluginException('No handler for ${call.method}');
      }

      final existingPreparation = _terminationPreparation;
      if (existingPreparation != null) {
        await existingPreparation;
        return;
      }

      final preparation = onTerminationRequested(
        _decodeOccurrence(call.arguments),
      );
      _terminationPreparation = preparation;
      await preparation;
    });
    try {
      await _channel.invokeMethod<void>('lifecycleReady');
    } on MissingPluginException {
      // Older or unsupported native runners can still use the Dart fallback.
    }
  }

  NativeTerminationOccurrence _decodeOccurrence(Object? arguments) {
    if (arguments is! Map<Object?, Object?>) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'Expected a native termination argument map.',
      );
    }

    final occurredAtUtc = arguments['occurredAtUtc'];
    if (occurredAtUtc is! String) {
      throw ArgumentError.value(
        occurredAtUtc,
        'occurredAtUtc',
        'Expected an ISO-8601 timestamp.',
      );
    }

    return NativeTerminationOccurrence(
      occurredAtUtc: DateTime.parse(occurredAtUtc).toUtc(),
    );
  }
}
