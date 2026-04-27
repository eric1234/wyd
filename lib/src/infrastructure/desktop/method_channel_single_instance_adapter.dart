import 'package:flutter/services.dart';

import '../../application/application.dart';

final class MethodChannelSingleInstanceAdapter
    implements SingleInstanceAdapter {
  MethodChannelSingleInstanceAdapter({
    MethodChannel channel = const MethodChannel(
      'dev.wyd.tracker/single_instance',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> initialize(
    Future<void> Function() onSecondInstanceActivated,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'secondInstanceActivated') {
        await onSecondInstanceActivated();
      }
    });
  }
}
