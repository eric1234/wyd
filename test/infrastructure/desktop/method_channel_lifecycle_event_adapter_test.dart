import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channelName = 'dev.wyd.tracker/test_lifecycle_events';
  const channel = MethodChannel(channelName);
  const codec = StandardMethodCodec();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'decodes every lifecycle kind and waits for persistence callback',
    () async {
      final adapter = MethodChannelLifecycleEventAdapter(channel: channel);
      final occurrences = <LifecycleEventOccurrence>[];
      final completion = Completer<void>();
      await adapter.initialize((occurrence) async {
        occurrences.add(occurrence);
        if (occurrence.kind == LifecycleEventKind.sleep) {
          await completion.future;
        }
      });

      ByteData? response;
      final pending = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            channelName,
            codec.encodeMethodCall(
              const MethodCall('lifecycleEvent', {
                'kind': 'sleep',
                'occurredAtUtc': '2026-01-01T09:30:00.000Z',
              }),
            ),
            (data) => response = data,
          );
      await Future<void>.delayed(Duration.zero);
      expect(response, isNull);
      completion.complete();
      await pending;
      codec.decodeEnvelope(response!);

      for (final kind in const [
        'lock',
        'shutdown',
        'shutdown_cancelled',
        'termination',
      ]) {
        await _send(channelName, kind);
      }
      expect(occurrences.map((value) => value.kind), [
        LifecycleEventKind.sleep,
        LifecycleEventKind.lock,
        LifecycleEventKind.shutdown,
        LifecycleEventKind.shutdownCancelled,
        LifecycleEventKind.termination,
      ]);
    },
  );
}

Future<void> _send(String channelName, String kind) async {
  ByteData? response;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('lifecycleEvent', {
            'kind': kind,
            'occurredAtUtc': '2026-01-01T09:30:00.000Z',
          }),
        ),
        (data) => response = data,
      );
  const StandardMethodCodec().decodeEnvelope(response!);
}
