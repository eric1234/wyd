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
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
      expect(bindings.userIdleDetector, isA<UnsupportedUserIdleDetector>());
    });

    test('exposes injected Linux D-Bus power adapter', () {
      final lifecycleEventAdapter = _FakeLifecycleEventAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxLifecycleEventAdapterFactory: () => lifecycleEventAdapter,
      );

      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.lifecycleEventAdapter, same(lifecycleEventAdapter));
    });

    test('uses Linux power adapter as lifecycle adapter when supported', () {
      final adapter = _FakeLinuxLifecyclePowerAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxLifecycleEventAdapterFactory: () => adapter,
      );

      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.lifecycleEventAdapter, same(adapter));
    });

    test('skips Linux power and lifecycle adapters when excluded', () {
      var powerFactoryCalls = 0;
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        includePowerLifecycleAdapters: false,
        linuxLifecycleEventAdapterFactory: () {
          powerFactoryCalls += 1;
          return _FakeLinuxLifecyclePowerAdapter();
        },
      );

      expect(powerFactoryCalls, 0);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
    });

    test('falls back when Linux power adapter factory returns null', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxLifecycleEventAdapterFactory: () => null,
      );

      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
    });

    test('falls back when Linux power adapter factory fails', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxLifecycleEventAdapterFactory: () =>
            throw StateError('D-Bus failed'),
      );

      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
    });

    test(
      'enables macOS tray lifecycle, acknowledged power, and start-at-login bindings',
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
          bindings.lifecycleEventAdapter,
          isA<MethodChannelLifecycleEventAdapter>(),
        );
        expect(bindings.userIdleDetector, isA<UnsupportedUserIdleDetector>());
      },
    );

    test('skips macOS power and lifecycle adapters when excluded', () {
      var powerFactoryCalls = 0;
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: false,
        isMacOS: true,
        includePowerLifecycleAdapters: false,
        macOSLifecycleEventAdapterFactory: () {
          powerFactoryCalls += 1;
          return const MethodChannelLifecycleEventAdapter();
        },
      );

      expect(powerFactoryCalls, 0);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
    });

    test('enables Windows tray, power, and start-at-login bindings', () {
      final startupAtLogin = _FakeStartupAtLoginAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: false,
        isMacOS: false,
        isWindows: true,
        windowsStartupAtLoginFactory: () => startupAtLogin,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isTrue);
      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.capabilities.supportsTrayClickActions, isTrue);
      expect(bindings.startupAtLoginAdapter, same(startupAtLogin));
      expect(
        bindings.lifecycleEventAdapter,
        isA<MethodChannelLifecycleEventAdapter>(),
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
      expect(
        bindings.lifecycleEventAdapter,
        isA<UnsupportedLifecycleEventAdapter>(),
      );
    });

    test(
      'exposes injected user idle detector capability on supported desktops',
      () {
        for (final platform in const [
          (isLinux: true, isMacOS: false, isWindows: false),
          (isLinux: false, isMacOS: true, isWindows: false),
          (isLinux: false, isMacOS: false, isWindows: true),
        ]) {
          final userIdleDetector = _FakeUserIdleDetector();
          final bindings = DesktopPlatformBindings.forPlatform(
            isLinux: platform.isLinux,
            isMacOS: platform.isMacOS,
            isWindows: platform.isWindows,
            linuxStartupAtLoginFactory: () => _FakeStartupAtLoginAdapter(),
            macOSStartupAtLoginFactory: () => _FakeStartupAtLoginAdapter(),
            windowsStartupAtLoginFactory: () => _FakeStartupAtLoginAdapter(),
            supportsUserIdleDetection: true,
            userIdleDetector: userIdleDetector,
          );

          expect(bindings.capabilities.supportsUserIdleDetection, isTrue);
          expect(bindings.userIdleDetector, same(userIdleDetector));
        }
      },
    );
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

final class _FakeLifecycleEventAdapter implements LifecycleEventAdapter {
  @override
  Future<void> initialize(
    Future<void> Function(LifecycleEventOccurrence occurrence) onEvent,
  ) async {}
}

final class _FakeLinuxLifecyclePowerAdapter implements LifecycleEventAdapter {
  @override
  Future<void> initialize(
    Future<void> Function(LifecycleEventOccurrence occurrence) onEvent,
  ) async {}
}
