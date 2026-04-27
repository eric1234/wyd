import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SingleFlutterWindowAdapter', () {
    const windowManagerChannel = MethodChannel('window_manager');
    const screenRetrieverChannel = MethodChannel(
      'dev.leanflutter.plugins/screen_retriever',
    );
    late List<MethodCall> windowCalls;

    setUp(() {
      windowCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
            windowCalls.add(call);
            return switch (call.method) {
              'isFullScreen' ||
              'isMaximized' ||
              'isMinimized' ||
              'isVisible' ||
              'isPreventClose' => false,
              'getBounds' => {
                'x': 0.0,
                'y': 0.0,
                'width': 520.0,
                'height': 460.0,
              },
              _ => true,
            };
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(screenRetrieverChannel, (call) async {
            return switch (call.method) {
              'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
              'getPrimaryDisplay' => _display(),
              'getAllDisplays' => {
                'displays': [_display()],
              },
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(screenRetrieverChannel, null);
    });

    test('applies role size before showing the native window', () async {
      final adapter = SingleFlutterWindowAdapter();
      final reportConfiguration = WindowRoleConfiguration.forRole(
        WindowRole.report,
      );

      await adapter.open(reportConfiguration);

      final reportSizeIndex = windowCalls.indexWhere((call) {
        if (call.method != 'setBounds') {
          return false;
        }
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        return arguments['width'] == reportConfiguration.width &&
            arguments['height'] == reportConfiguration.height;
      });
      final showIndex = windowCalls.indexWhere((call) => call.method == 'show');

      expect(reportSizeIndex, greaterThanOrEqualTo(0));
      expect(showIndex, greaterThanOrEqualTo(0));
      expect(reportSizeIndex, lessThan(showIndex));
    });
  });
}

Map<String, Object?> _display() {
  return {
    'id': 'primary',
    'name': 'Primary',
    'size': {'width': 1920.0, 'height': 1080.0},
    'visiblePosition': {'dx': 0.0, 'dy': 0.0},
    'visibleSize': {'width': 1920.0, 'height': 1080.0},
    'scaleFactor': 1.0,
  };
}
