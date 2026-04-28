import 'dart:io';

import '../../application/application.dart';
import 'xdg_autostart_startup_adapter.dart';

final class DesktopPlatformBindings {
  const DesktopPlatformBindings({
    required this.capabilities,
    required this.startupAtLoginAdapter,
    required this.powerEventAdapter,
    required this.typingActivityDetector,
  });

  factory DesktopPlatformBindings.current() {
    return DesktopPlatformBindings.forPlatform(isLinux: Platform.isLinux);
  }

  factory DesktopPlatformBindings.forPlatform({
    required bool isLinux,
    StartupAtLoginAdapter Function()? linuxStartupAtLoginFactory,
  }) {
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsStartAtLogin: isLinux,
        supportsTrayClickActions: true,
      ),
      startupAtLoginAdapter: isLinux
          ? (linuxStartupAtLoginFactory?.call() ??
                XdgAutostartStartupAtLoginAdapter())
          : const UnsupportedStartupAtLoginAdapter(),
      powerEventAdapter: const UnsupportedPowerEventAdapter(),
      typingActivityDetector: const UnsupportedTypingActivityDetector(),
    );
  }

  final PlatformCapabilities capabilities;
  final StartupAtLoginAdapter startupAtLoginAdapter;
  final PowerEventAdapter powerEventAdapter;
  final TypingActivityDetector typingActivityDetector;
}
