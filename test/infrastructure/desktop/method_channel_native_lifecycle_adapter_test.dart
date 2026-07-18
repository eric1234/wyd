import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
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
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('announces readiness after installing the handler', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);

      await adapter.initialize((_) async {});

      expect(nativeCalls.map((call) => call.method), ['lifecycleReady']);
    });

    test('decodes timestamped native termination preparation', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
      NativeTerminationOccurrence? occurrence;
      await adapter.initialize((value) async {
        occurrence = value;
      });

      await _sendMethodCall(
        channelName,
        const MethodCall('prepareForTermination', {
          'occurredAtUtc': '2026-01-01T09:30:00.000Z',
        }),
      );

      expect(occurrence?.occurredAtUtc, DateTime.utc(2026, 1, 1, 9, 30));
    });

    test('repeated requests await the same preparation', () async {
      final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
      final preparation = Completer<void>();
      var calls = 0;
      await adapter.initialize((_) async {
        calls += 1;
        await preparation.future;
      });

      final firstResponse = _sendMethodCall(
        channelName,
        const MethodCall('prepareForTermination', {
          'occurredAtUtc': '2026-01-01T09:30:00.000Z',
        }),
      );
      final secondResponse = _sendMethodCall(
        channelName,
        const MethodCall('prepareForTermination', {
          'occurredAtUtc': '2026-01-01T09:31:00.000Z',
        }),
      );
      var firstCompleted = false;
      var secondCompleted = false;
      firstResponse.then((_) => firstCompleted = true);
      secondResponse.then((_) => secondCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);

      preparation.complete();
      await Future.wait([firstResponse, secondResponse]);
    });

    test(
      'surfaces malformed termination payloads as platform errors',
      () async {
        final adapter = MethodChannelNativeLifecycleAdapter(channel: channel);
        var calls = 0;
        await adapter.initialize((_) async {
          calls += 1;
        });

        await expectLater(
          () => _sendMethodCall(
            channelName,
            const MethodCall('prepareForTermination', {}),
          ),
          throwsA(isA<PlatformException>()),
        );

        expect(calls, 0);
      },
    );
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
