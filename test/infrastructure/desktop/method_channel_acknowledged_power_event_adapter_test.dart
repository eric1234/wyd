import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelAcknowledgedPowerEventAdapter', () {
    const channelName = 'dev.wyd.tracker/test_power_events_ack';
    const channel = MethodChannel(channelName);
    const codec = StandardMethodCodec();
    late List<MethodCall> nativeCalls;

    setUp(() {
      nativeCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('announces readiness after installing the handler', () async {
      final adapter = MethodChannelAcknowledgedPowerEventAdapter(
        channel: channel,
      );

      await adapter.initializeAcknowledged((_) async {});

      expect(nativeCalls.map((call) => call.method), ['powerEventsReady']);
    });

    test('decodes native power event occurrences', () async {
      final adapter = MethodChannelAcknowledgedPowerEventAdapter(
        channel: channel,
      );
      final occurrences = <PowerEventOccurrence>[];
      await adapter.initializeAcknowledged((value) async {
        occurrences.add(value);
      });

      await _sendMethodCall(
        channelName,
        const MethodCall('powerEvent', {
          'event': 'sleep',
          'occurredAtUtc': '2026-01-01T09:30:00.000Z',
        }),
      );
      await _sendMethodCall(
        channelName,
        const MethodCall('powerEvent', {
          'event': 'shutdown',
          'occurredAtUtc': '2026-01-01T09:45:00.000Z',
        }),
      );
      await _sendMethodCall(
        channelName,
        const MethodCall('powerEvent', {
          'event': 'shutdown_cancelled',
          'occurredAtUtc': '2026-01-01T09:46:00.000Z',
        }),
      );

      expect(occurrences[0].event, PowerEvent.sleep);
      expect(occurrences[0].occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 30));
      expect(occurrences[1].event, PowerEvent.shutdown);
      expect(occurrences[1].occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 45));
      expect(occurrences[2].event, PowerEvent.shutdownCancelled);
      expect(occurrences[2].occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 46));
    });

    test('responds only after the callback completes', () async {
      final adapter = MethodChannelAcknowledgedPowerEventAdapter(
        channel: channel,
      );
      final callbackCompleter = Completer<void>();
      await adapter.initializeAcknowledged((_) => callbackCompleter.future);

      ByteData? response;
      final messageFuture = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            channelName,
            codec.encodeMethodCall(
              const MethodCall('powerEvent', {
                'event': 'lock',
                'occurredAtUtc': '2026-01-01T09:30:00.000Z',
              }),
            ),
            (data) => response = data,
          );

      await Future<void>.delayed(Duration.zero);
      expect(response, isNull);

      callbackCompleter.complete();
      await messageFuture;

      expect(response, isNotNull);
      codec.decodeEnvelope(response!);
    });

    test('surfaces unknown event strings as platform errors', () async {
      final adapter = MethodChannelAcknowledgedPowerEventAdapter(
        channel: channel,
      );
      await adapter.initializeAcknowledged((_) async {});

      await expectLater(() async {
        await _sendMethodCall(
          channelName,
          const MethodCall('powerEvent', {
            'event': 'wake',
            'occurredAtUtc': '2026-01-01T09:30:00.000Z',
          }),
        );
      }, throwsA(isA<PlatformException>()));
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
