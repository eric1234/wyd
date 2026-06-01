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
    late bool isFullScreen;
    late bool isMaximized;
    late bool isMinimized;
    late bool isVisible;
    late bool isFocused;
    late bool isPreventClose;

    setUp(() {
      windowCalls = [];
      isFullScreen = false;
      isMaximized = false;
      isMinimized = false;
      isVisible = false;
      isFocused = true;
      isPreventClose = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
            windowCalls.add(call);
            return switch (call.method) {
              'isFullScreen' => isFullScreen,
              'isMaximized' => isMaximized,
              'isMinimized' => isMinimized,
              'isVisible' => isVisible,
              'isFocused' => isFocused,
              'isPreventClose' => isPreventClose,
              'setFullScreen' => isFullScreen = _boolArgument(
                call.arguments,
                'isFullScreen',
              ),
              'unmaximize' => isMaximized = false,
              'restore' => isMinimized = false,
              'show' => isVisible = true,
              'focus' => isFocused = true,
              'hide' => isVisible = false,
              'close' => isVisible = false,
              'setPreventClose' => isPreventClose = _boolArgument(
                call.arguments,
                'isPreventClose',
              ),
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

    SingleFlutterWindowAdapter buildAdapter([
      _FakeWindowAttentionAdapter? windowAttentionAdapter,
    ]) {
      return SingleFlutterWindowAdapter(
        windowAttentionAdapter:
            windowAttentionAdapter ?? _FakeWindowAttentionAdapter(),
      );
    }

    test('applies role size before showing the native window', () async {
      final adapter = buildAdapter();
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

    test('applies quick-entry fixed-size window constraints', () async {
      final adapter = buildAdapter();

      await adapter.open(WindowRoleConfiguration.quickEntry());

      expect(
        windowCalls.any(
          (call) =>
              call.method == 'setAlwaysOnTop' &&
              _boolArgument(call.arguments, 'isAlwaysOnTop'),
        ),
        isTrue,
      );
      expect(
        windowCalls.any(
          (call) =>
              call.method == 'setSkipTaskbar' &&
              _boolArgument(call.arguments, 'isSkipTaskbar'),
        ),
        isTrue,
      );
      expect(
        windowCalls.any(
          (call) =>
              call.method == 'setResizable' &&
              !_boolArgument(call.arguments, 'isResizable'),
        ),
        isTrue,
      );
      expect(
        windowCalls.where((call) {
          if (call.method != 'setBounds') {
            return false;
          }
          final arguments = Map<Object?, Object?>.from(call.arguments as Map);
          return arguments['width'] ==
                  WindowRoleConfiguration.quickEntryWidth &&
              arguments['height'] == WindowRoleConfiguration.quickEntryHeight;
        }),
        isNotEmpty,
      );
    });

    test('hides resident startup window when no role is open', () async {
      final adapter = buildAdapter();

      await adapter.hideResidentWindow();

      expect(windowCalls.any((call) => call.method == 'hide'), isTrue);
    });

    test('does not hide an open role window as resident startup', () async {
      final adapter = buildAdapter();
      await adapter.open(WindowRoleConfiguration.quickEntry());
      windowCalls.clear();

      await adapter.hideResidentWindow();

      expect(windowCalls.any((call) => call.method == 'hide'), isFalse);
    });

    test('uses native window attention when focusing primary window', () async {
      final attentionAdapter = _FakeWindowAttentionAdapter();
      final adapter = buildAdapter(attentionAdapter);
      final handle = await adapter.open(WindowRoleConfiguration.quickEntry());
      windowCalls.clear();
      attentionAdapter.clear();

      await adapter.focus(handle);

      expect(windowCalls.where((call) => call.method == 'show'), hasLength(1));
      expect(windowCalls.where((call) => call.method == 'focus'), isEmpty);
      expect(attentionAdapter.calls, contains('presentForInput'));
      expect(attentionAdapter.urgentValues.last, isFalse);
    });

    test(
      'falls back to window manager focus without native attention',
      () async {
        final attentionAdapter = _FakeWindowAttentionAdapter(
          presentResult: false,
        );
        final adapter = buildAdapter(attentionAdapter);
        final handle = await adapter.open(WindowRoleConfiguration.quickEntry());
        windowCalls.clear();
        attentionAdapter.clear();

        await adapter.focus(handle);

        expect(attentionAdapter.calls, contains('presentForInput'));
        expect(
          windowCalls.where((call) => call.method == 'focus'),
          hasLength(1),
        );
      },
    );

    test('marks shown window urgent when focus is denied', () async {
      final attentionAdapter = _FakeWindowAttentionAdapter();
      final adapter = buildAdapter(attentionAdapter);
      final handle = await adapter.open(WindowRoleConfiguration.quickEntry());
      windowCalls.clear();
      attentionAdapter.clear();
      isFocused = false;

      await adapter.focus(handle);

      expect(windowCalls.where((call) => call.method == 'show'), hasLength(1));
      expect(windowCalls.where((call) => call.method == 'focus'), isEmpty);
      expect(attentionAdapter.urgentValues, [false, true]);
    });

    test('clears urgency before hiding the native window', () async {
      final attentionAdapter = _FakeWindowAttentionAdapter();
      final adapter = buildAdapter(attentionAdapter);
      final handle = await adapter.open(WindowRoleConfiguration.quickEntry());
      windowCalls.clear();
      attentionAdapter.clear();

      await adapter.close(handle);

      expect(attentionAdapter.urgentValues, [false]);
      expect(windowCalls.any((call) => call.method == 'hide'), isTrue);
    });

    test(
      'normalizes fullscreen maximized and minimized states before sizing',
      () async {
        isFullScreen = true;
        isMaximized = true;
        isMinimized = true;
        final adapter = buildAdapter();

        await adapter.open(
          WindowRoleConfiguration.forRole(WindowRole.settings),
        );

        expect(
          windowCalls.any(
            (call) =>
                call.method == 'setFullScreen' &&
                !_boolArgument(call.arguments, 'isFullScreen'),
          ),
          isTrue,
        );
        expect(windowCalls.any((call) => call.method == 'unmaximize'), isTrue);
        expect(windowCalls.any((call) => call.method == 'restore'), isTrue);
      },
    );

    test(
      'native close hides and emits close request for current handle',
      () async {
        final adapter = buildAdapter();
        final handle = await adapter.open(WindowRoleConfiguration.quickEntry());

        final closeRequest = expectLater(
          adapter.closeRequests,
          emits(predicate<WindowHandle>((closed) => closed.id == handle.id)),
        );
        adapter.onWindowClose();
        await closeRequest;

        expect(windowCalls.any((call) => call.method == 'hide'), isTrue);
      },
    );
  });

  group('HideOnCloseWindowHandler', () {
    const windowManagerChannel = MethodChannel('window_manager');
    late List<MethodCall> windowCalls;
    late bool isPreventClose;

    setUp(() {
      windowCalls = [];
      isPreventClose = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
            windowCalls.add(call);
            return switch (call.method) {
              'isPreventClose' => isPreventClose,
              'setPreventClose' => isPreventClose = _boolArgument(
                call.arguments,
                'isPreventClose',
              ),
              _ => true,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, null);
    });

    test('hides instead of closing and runs before-hide callback', () async {
      var beforeHideCalls = 0;
      final handler = HideOnCloseWindowHandler(
        onBeforeHide: () async {
          beforeHideCalls += 1;
        },
      );
      await handler.initialize();

      handler.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(beforeHideCalls, 1);
      expect(windowCalls.any((call) => call.method == 'hide'), isTrue);
      expect(windowCalls.any((call) => call.method == 'close'), isFalse);
    });

    test('forceClose disables close interception and closes window', () async {
      final handler = HideOnCloseWindowHandler();
      await handler.initialize();

      await handler.forceClose();

      expect(
        windowCalls.any(
          (call) =>
              call.method == 'setPreventClose' &&
              !_boolArgument(call.arguments, 'isPreventClose'),
        ),
        isTrue,
      );
      expect(windowCalls.any((call) => call.method == 'close'), isTrue);
    });
  });
}

bool _boolArgument(Object? arguments, String key) {
  if (arguments is bool) {
    return arguments;
  }
  if (arguments is Map) {
    return Map<Object?, Object?>.from(arguments)[key] as bool;
  }
  throw ArgumentError.value(arguments, 'arguments', 'Expected bool argument.');
}

final class _FakeWindowAttentionAdapter implements WindowAttentionAdapter {
  _FakeWindowAttentionAdapter({this.presentResult = true});

  bool presentResult;
  final List<String> calls = [];
  final List<bool> urgentValues = [];

  @override
  Future<bool> presentForInput() async {
    calls.add('presentForInput');
    return presentResult;
  }

  @override
  Future<void> setUrgent(bool urgent) async {
    calls.add('setUrgent');
    urgentValues.add(urgent);
  }

  void clear() {
    calls.clear();
    urgentValues.clear();
  }
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
