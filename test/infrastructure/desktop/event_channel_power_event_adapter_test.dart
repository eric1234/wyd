import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EventChannelPowerEventAdapter', () {
    const channelName = 'dev.wyd.tracker/test_power_events';
    const channel = EventChannel(channelName);
    const codec = StandardMethodCodec();
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(channelName, (message) async {
            final call = codec.decodeMethodCall(message);
            methodCalls.add(call);
            return codec.encodeSuccessEnvelope(null);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(channelName, null);
    });

    test('maps native event strings to power events', () async {
      final adapter = EventChannelPowerEventAdapter(channel: channel);
      final expectation = expectLater(
        adapter.events,
        emitsInOrder([PowerEvent.sleep, PowerEvent.lock]),
      );

      await Future<void>.delayed(Duration.zero);
      await _sendEvent(channelName, 'sleep');
      await _sendEvent(channelName, 'lock');

      await expectation;
      expect(methodCalls.map((call) => call.method), contains('listen'));
    });

    test('surfaces unknown native event strings as stream errors', () async {
      final adapter = EventChannelPowerEventAdapter(channel: channel);
      final expectation = expectLater(
        adapter.events,
        emitsError(isA<ArgumentError>()),
      );

      await Future<void>.delayed(Duration.zero);
      await _sendEvent(channelName, 'wake');

      await expectation;
    });
  });
}

Future<void> _sendEvent(String channelName, Object? event) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    channelName,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    (_) {},
  );
}
