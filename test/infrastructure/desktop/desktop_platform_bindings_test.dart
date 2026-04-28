import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('DesktopPlatformBindings', () {
    test('uses XDG-compatible start-at-login on Linux', () {
      final startupAtLogin = _FakeStartupAtLoginAdapter();
      final bindings = DesktopPlatformBindings.forPlatform(
        isLinux: true,
        linuxStartupAtLoginFactory: () => startupAtLogin,
      );

      expect(bindings.capabilities.supportsStartAtLogin, isTrue);
      expect(bindings.capabilities.supportsTrayClickActions, isTrue);
      expect(bindings.startupAtLoginAdapter, same(startupAtLogin));
      expect(bindings.powerEventAdapter, isA<UnsupportedPowerEventAdapter>());
      expect(
        bindings.typingActivityDetector,
        isA<UnsupportedTypingActivityDetector>(),
      );
    });

    test('does not expose Linux start-at-login on other platforms', () {
      final bindings = DesktopPlatformBindings.forPlatform(isLinux: false);

      expect(bindings.capabilities.supportsStartAtLogin, isFalse);
      expect(
        bindings.startupAtLoginAdapter,
        isA<UnsupportedStartupAtLoginAdapter>(),
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
