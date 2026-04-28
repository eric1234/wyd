import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrayManagerAdapter', () {
    const channel = MethodChannel('tray_manager');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'secondary tray click opens the context menu when supported',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: true);

        adapter.onTrayIconRightMouseDown();
        await Future<void>.delayed(Duration.zero);

        expect(calls.map((call) => call.method), contains('popUpContextMenu'));
      },
    );

    test(
      'primary tray click emits quick-entry action when secondary menu is supported',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: true);
        final click = expectLater(adapter.primaryClicks, emits(null));

        adapter.onTrayIconMouseDown();

        await click;
      },
    );

    test(
      'primary tray click is left to native menu fallback without secondary support',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: false);
        var primaryClicks = 0;
        final subscription = adapter.primaryClicks.listen((_) {
          primaryClicks += 1;
        });
        addTearDown(subscription.cancel);

        adapter.onTrayIconMouseDown();
        await Future<void>.delayed(Duration.zero);

        expect(primaryClicks, 0);
        expect(calls, isEmpty);
      },
    );

    test('secondary tray click is ignored without secondary support', () async {
      final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: false);

      adapter.onTrayIconRightMouseDown();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });
}
