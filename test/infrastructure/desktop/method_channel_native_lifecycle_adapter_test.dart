import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelNativeLifecycleAdapter', () {
    const channelName = 'dev.wyd.tracker/test_lifecycle';
    const channel = MethodChannel(channelName);
    late List<MethodCall> nativeCalls;

    setUp(() {
      nativeCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('announces readiness after installing the handler', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);

      await adapter.initialize(() async {});

      expect(nativeCalls.map((call) => call.method), ['lifecycleReady']);
    });

    test('invokes callback for native termination requests', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
      var calls = 0;
      await adapter.initialize(() async {
        calls += 1;
      });

      await _sendMethodCall(
        channelName,
        const MethodCall('terminationRequested'),
      );

      expect(calls, 1);
    });

    test('ignores repeated termination requests', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
      var calls = 0;
      await adapter.initialize(() async {
        calls += 1;
      });

      await _sendMethodCall(
        channelName,
        const MethodCall('terminationRequested'),
      );
      await _sendMethodCall(
        channelName,
        const MethodCall('terminationRequested'),
      );

      expect(calls, 1);
    });

    test('ignores unknown native method calls', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
      var calls = 0;
      await adapter.initialize(() async {
        calls += 1;
      });

      await _sendMethodCall(channelName, const MethodCall('unknown'));

      expect(calls, 0);
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
