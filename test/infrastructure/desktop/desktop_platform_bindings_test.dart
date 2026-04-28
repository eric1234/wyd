import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('DesktopPlatformBindings', () {
    test('uses XDG-compatible start-at-login on Linux', () {
      final startupAtLogin = _FakeStartupAtLoginAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxStartupAtLoginFactory: () => startupAtLogin,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isTrue);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.capabilities.supportsTrayClickActions, isFalse);
      expect(bindings.startupAtLoginAdapter, same(startupAtLogin));
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(
        bindings.typingActivityDetector,
        isA<UnsupportedTypingActivityDetector>(),
      );
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });

    test('enables macOS tray lifecycle and power bindings', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: false,
        isMacOS: true,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isFalse);
      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.capabilities.supportsTypingActivity, isFalse);
      expect(bindings.capabilities.supportsTrayClickActions, isTrue);
      expect(bindings.capabilities.supportsTrayRelativePositioning, isFalse);
      expect(
        bindings.startupAtLoginAdapter,
        isA<UnsupportedStartupAtLoginAdapter>(),
      );
      expect(bindings.powerEventAdapter, isA<EventChannelPowerEventAdapter>());
      expect(
        bindings.typingActivityDetector,
        isA<UnsupportedTypingActivityDetector>(),
      );
      expect(
        bindings.nativeLifecycleAdapter,
        isA<MethodChannelNativeLifecycleAdapter>(),
      );
    });

    test('does not expose Linux start-at-login on other platforms', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: false,
        isMacOS: false,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isFalse);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.capabilities.supportsTrayClickActions, isFalse);
      expect(
        bindings.startupAtLoginAdapter,
        isA<UnsupportedStartupAtLoginAdapter>(),
      );
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });
  });
}

final class _FakeStartupAtLoginAdapter implements StartupAtLoginAdapter {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}
