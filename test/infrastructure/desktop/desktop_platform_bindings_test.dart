import 'dart:async';

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

    test('exposes injected Linux D-Bus power adapter', () {
      final powerEventAdapter = _FakePowerEventAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxPowerEventAdapterFactory: () => powerEventAdapter,
      );

      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.powerEventAdapter, same(powerEventAdapter));
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });

    test('uses Linux power adapter as lifecycle adapter when supported', () {
      final adapter = _FakeLinuxLifecyclePowerAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxPowerEventAdapterFactory: () => adapter,
      );

      expect(bindings.capabilities.supportsPowerEvents, isTrue);
      expect(bindings.powerEventAdapter, same(adapter));
      expect(bindings.nativeLifecycleAdapter, same(adapter));
    });

    test('skips Linux power and lifecycle adapters when excluded', () {
      var powerFactoryCalls = 0;
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        includePowerLifecycleAdapters: false,
        linuxPowerEventAdapterFactory: () {
          powerFactoryCalls += 1;
          return _FakeLinuxLifecyclePowerAdapter();
        },
      );

      expect(powerFactoryCalls, 0);
      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(
        bindings.nativeLifecycleAdapter,
        isA<UnsupportedNativeLifecycleAdapter>(),
      );
    });

    test('falls back when Linux power adapter factory returns null', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxPowerEventAdapterFactory: () => null,
      );

      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
    });

    test('falls back when Linux power adapter factory fails', () {
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        isMacOS: false,
        linuxPowerEventAdapterFactory: () => throw StateError('D-Bus failed'),
      );

      expect(bindings.capabilities.supportsPowerEvents, isFalse);
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
    });

    test(
      'enables macOS tray lifecycle, plugin power, and start-at-login bindings',
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
          isA<DesktopScreenStatePowerEventAdapter>(),
        );
        expect(bindings.userIdleDetector, isA<UnsupportedUserIdleDetector>());
        expect(
          bindings.nativeLifecycleAdapter,
          isA<MethodChannelNativeLifecycleAdapter>(),
        );
      },
    );

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
        bindings.powerEventAdapter,
        isA<MethodChannelAcknowledgedPowerEventAdapter>(),
      );
      expect(
        bindings.nativeLifecycleAdapter,
        isA<MethodChannelNativeLifecycleAdapter>(),
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

final class _FakePowerEventAdapter implements PowerEventAdapter {
  @override
  Stream<PowerEvent> get events => const Stream.empty();
}

final class _FakeLinuxLifecyclePowerAdapter
    implements PowerEventAdapter, NativeLifecycleAdapter {
  @override
  Stream<PowerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize(
    Future<void> Function() onTerminationRequested,
  ) async {}
}
