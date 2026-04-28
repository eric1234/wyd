import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelSingleInstanceAdapter', () {
    const channelName = 'dev.wyd.tracker/test_single_instance';
    const channel = MethodChannel(channelName);

    test('invokes callback for second-instance activation', () async {
      final adapter = MethodChannelSingleInstanceAdapter(channel: channel);
      var calls = 0;
      await adapter.initialize(() async {
        calls += 1;
      });

      await _sendMethodCall(
        channelName,
        const MethodCall('secondInstanceActivated'),
      );

      expect(calls, 1);
    });

    test('ignores unknown native method calls', () async {
      final adapter = MethodChannelSingleInstanceAdapter(channel: channel);
      var calls = 0;
      await adapter.initialize(() async {
        calls += 1;
      });

      await _sendMethodCall(channelName, const MethodCall('unknown'));

      expect(calls, 0);
    });

    test('consumes pending native activation during initialization', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'consumePendingActivation') {
          return true;
        }
        return null;
      });
      final adapter = MethodChannelSingleInstanceAdapter(channel: channel);
      var calls = 0;

      await adapter.initialize(() async {
        calls += 1;
      });

      expect(calls, 1);
    });
  });
}

Future<void> _sendMethodCall(String channelName, MethodCall call) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  ByteData? response;
  await messenger.handlePlatformMessage(
    channelName,
    const StandardMethodCodec().encodeMethodCall(call),
    (data) => response = data,
  );
  if (response != null) {
    const StandardMethodCodec().decodeEnvelope(response!);
  }
}
