import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('role window argument encoding', () {
    test('round-trips role and show-on-ready flag', () {
      final arguments = encodeRoleWindowArguments(
        WindowRole.about,
        showOnReady: false,
      );

      expect(decodeRoleWindowRole(arguments), WindowRole.about);
      expect(decodeRoleWindowShowOnReady(arguments), isFalse);
    });

    test('returns null role for invalid arguments', () {
      expect(decodeRoleWindowRole(''), isNull);
      expect(decodeRoleWindowRole('not-json'), isNull);
      expect(decodeRoleWindowRole('{"kind":"other","role":"report"}'), isNull);
      expect(
        decodeRoleWindowRole('{"kind":"wyd-role-window","role":"missing"}'),
        isNull,
      );
    });

    test('defaults show-on-ready to true for invalid arguments', () {
      expect(decodeRoleWindowShowOnReady(''), isTrue);
      expect(decodeRoleWindowShowOnReady('not-json'), isTrue);
      expect(decodeRoleWindowShowOnReady('{"kind":"wyd-role-window"}'), isTrue);
    });
  });

  group('role window configuration encoding', () {
    test('round-trips window configuration maps', () {
      final configuration = WindowRoleConfiguration.forRole(WindowRole.about);

      final decoded = decodeRoleWindowConfiguration(
        encodeRoleWindowConfiguration(configuration),
      );

      expect(decoded.role, configuration.role);
      expect(decoded.title, configuration.title);
      expect(decoded.width, configuration.width);
      expect(decoded.height, configuration.height);
      expect(decoded.resizable, configuration.resizable);
      expect(decoded.alwaysOnTop, configuration.alwaysOnTop);
    });

    test('throws format exceptions for malformed configuration maps', () {
      expect(
        () => decodeRoleWindowConfiguration(null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeRoleWindowConfiguration({'role': 'missing'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeRoleWindowConfiguration({
          'role': 'report',
          'title': 'Report',
          'width': 'wide',
          'height': 560,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DesktopMultiWindowAdapter', () {
    const windowsChannel = MethodChannel('mixin.one/desktop_multi_window');
    const windowMethodsChannel = MethodChannel(
      'mixin.one/desktop_multi_window/channels',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowMethodsChannel, null);
    });

    test('closes and forgets a child that never becomes ready', () async {
      final invokedChildMethods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, (call) async {
            return switch (call.method) {
              'createWindow' => 'about-test',
              'getAllWindows' => <Object?>[],
              _ => throw MissingPluginException(),
            };
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowMethodsChannel, (call) async {
            if (call.method != 'invokeMethod') {
              return null;
            }
            final arguments = Map<Object?, Object?>.from(call.arguments as Map);
            final method = arguments['method']! as String;
            invokedChildMethods.add(method);
            if (method == RoleWindowProtocol.pingMethod) {
              return false;
            }
            return null;
          });
      final primaryWindow = _FakeWindowAdapter();
      final adapter = DesktopMultiWindowAdapter(
        primaryWindowAdapter: primaryWindow,
        childWindowReadyPollInterval: Duration.zero,
        childWindowReadyMaxAttempts: 1,
      );
      addTearDown(adapter.dispose);
      addTearDown(primaryWindow.dispose);

      await expectLater(
        adapter.open(WindowRoleConfiguration.forRole(WindowRole.about)),
        throwsA(isA<StateError>()),
      );

      expect(invokedChildMethods, [
        RoleWindowProtocol.pingMethod,
        RoleWindowProtocol.closeMethod,
      ]);
    });
  });
}

final class _FakeWindowAdapter implements WindowAdapter {
  final StreamController<WindowHandle> _closeRequests =
      StreamController<WindowHandle>.broadcast();

  @override
  Stream<WindowHandle> get closeRequests => _closeRequests.stream;

  @override
  Future<void> close(WindowHandle handle) async {}

  @override
  Future<void> focus(WindowHandle handle) async {}

  @override
  Future<bool> isOpen(WindowHandle handle) async => false;

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async =>
      WindowHandle(configuration.role.name);

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) async =>
      WindowHandle(configuration.role.name);

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) async {}

  Future<void> dispose() => _closeRequests.close();
}
