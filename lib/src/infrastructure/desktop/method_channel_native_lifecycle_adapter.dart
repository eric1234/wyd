import 'package:flutter/services.dart';

import '../../application/application.dart';

final class MethodChannelNativeLifecycleAdapter
    implements NativeLifecycleAdapter {
  MethodChannelNativeLifecycleAdapter({
    MethodChannel channel = const MethodChannel('dev.wyd.tracker/lifecycle'),
  }) : _channel = channel;

  final MethodChannel _channel;
  bool _terminationRequested = false;

  @override
  Future<void> initialize(
    Future<void> Function() onTerminationRequested,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'terminationRequested') {
        if (_terminationRequested) {
          return;
        }
        _terminationRequested = true;
        await onTerminationRequested();
      }
    });
    try {
      await _channel.invokeMethod<void>('lifecycleReady');
    } on MissingPluginException {
      // Older or unsupported native runners can still use the Dart fallback.
    }
  }
}
