import 'dart:io';

import '../../application/application.dart';
import 'event_channel_power_event_adapter.dart';
import 'method_channel_native_lifecycle_adapter.dart';
import 'xdg_autostart_startup_adapter.dart';

final class DesktopPlatformBindings {
  const DesktopPlatformBindings({
    required this.capabilities,
    required this.startupAtLoginAdapter,
    required this.powerEventAdapter,
    required this.typingActivityDetector,
    required this.nativeLifecycleAdapter,
  });

  factory DesktopPlatformBindings.current() {
    return DesktopPlatformBindings.forPlatform(
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
    );
  }

  factory DesktopPlatformBindings.forPlatform({
    required bool isLinux,
    required bool isMacOS,
    StartupAtLoginAdapter Function()? linuxStartupAtLoginFactory,
    bool? supportsTrayClickActions,
  }) {
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsStartAtLogin: isLinux,
        supportsPowerEvents: isMacOS,
        supportsTrayClickActions: supportsTrayClickActions ?? isMacOS,
      ),
      startupAtLoginAdapter: isLinux
          ? (linuxStartupAtLoginFactory?.call() ??
                XdgAutostartStartupAtLoginAdapter())
          : const UnsupportedStartupAtLoginAdapter(),
      powerEventAdapter: isMacOS
          ? const EventChannelPowerEventAdapter()
          : const UnsupportedPowerEventAdapter(),
      typingActivityDetector: const UnsupportedTypingActivityDetector(),
      nativeLifecycleAdapter: isMacOS
          ? MethodChannelNativeLifecycleAdapter()
          : const UnsupportedNativeLifecycleAdapter(),
    );
  }

  final PlatformCapabilities capabilities;
  final StartupAtLoginAdapter startupAtLoginAdapter;
  final PowerEventAdapter powerEventAdapter;
  final TypingActivityDetector typingActivityDetector;
  final NativeLifecycleAdapter nativeLifecycleAdapter;
}
