import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('DesktopPlatformBindings', () {
    test('uses package-backed start-at-login on Linux', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isTrue);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.capabilities.supportsTrayClickActions, isFalse);
      expect(
        bindings.startupAtLoginAdapter,
        isA<LaunchAtStartupStartupAtLoginAdapter>(),
      );
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(bindings.userIdleDetector, isA<UnsupportedUserIdleDetector>());
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });

    test(
      'enables macOS tray lifecycle, power, and start-at-login bindings',
      () {
        final startupAtLogin = _FakeStartupAtLoginAdapter();
        final bindings = DesktopPlatformBindings.forPlatform(
          isLinux: false,
          isMacOS: true,
          macOSStartupAtLoginFactory: () => startupAtLogin,
        );

        expect(bindings.capabilities.supportsStartAtLogin, isTrue);
        expect(bindings.capabilities.supportsPowerEvents, isTrue);
        expect(bindings.capabilities.supportsUserIdleDetection, isFalse);
        expect(bindings.capabilities.supportsTrayClickActions, isTrue);
        expect(bindings.capabilities.supportsTrayRelativePositioning, isFalse);
        expect(bindings.startupAtLoginAdapter, same(startupAtLogin));
        expect(
          bindings.powerEventAdapter,
          isA<EventChannelPowerEventAdapter>(),
        );
        expect(bindings.userIdleDetector, isA<UnsupportedUserIdleDetector>());
        expect(
          bindings.nativeLifecycleAdapter,
          isA<MethodChannelNativeLifecycleAdapter>(),
        );
      },
    );

    test('exposes best-effort package-backed start-at-login on Windows', () {
      final startupAtLogin = _FakeStartupAtLoginAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: false,
        isMacOS: false,
        isWindows: true,
        windowsStartupAtLoginFactory: () => startupAtLogin,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isTrue);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.capabilities.supportsTrayClickActions, isFalse);
      expect(bindings.startupAtLoginAdapter, same(startupAtLogin));
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });

    test('does not expose start-at-login on unsupported platforms', () {
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

    test('exposes injected user idle detector capability', () {
      final userIdleDetector = _FakeUserIdleDetector();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxStartupAtLoginFactory: () => _FakeStartupAtLoginAdapter(),
        supportsUserIdleDetection: true,
        userIdleDetector: userIdleDetector,
      );

      expect(bindings.capabilities.supportsUserIdleDetection, isTrue);
      expect(bindings.userIdleDetector, same(userIdleDetector));
    });
  });
}

final class _FakeStartupAtLoginAdapter implements StartupAtLoginAdapter {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _FakeUserIdleDetector implements UserIdleDetector {
  @override
  Future<Duration?> promptDeferralFor(Duration minimumIdleDuration) async =>
      null;
}
