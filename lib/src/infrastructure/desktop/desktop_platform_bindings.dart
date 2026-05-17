import 'dart:io';

import '../../application/application.dart';
import 'event_channel_power_event_adapter.dart';
import 'method_channel_native_lifecycle_adapter.dart';
import 'system_idle_user_idle_detector.dart';
import 'xdg_autostart_startup_adapter.dart';

final class DesktopPlatformBindings {
  const DesktopPlatformBindings({
    required this.capabilities,
    required this.startupAtLoginAdapter,
    required this.powerEventAdapter,
    required this.userIdleDetector,
    required this.nativeLifecycleAdapter,
  });

  static Future<DesktopPlatformBindings> current() async {
    final userIdleDetector = await SystemIdleUserIdleDetector.create();
    return DesktopPlatformBindings.forPlatform(
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      supportsUserIdleDetection: userIdleDetector != null,
      userIdleDetector: userIdleDetector ?? const UnsupportedUserIdleDetector(),
    );
  }

  factory DesktopPlatformBindings.forPlatform({
    required bool isLinux,
    required bool isMacOS,
    StartupAtLoginAdapter Function()? linuxStartupAtLoginFactory,
    bool supportsUserIdleDetection = false,
    UserIdleDetector userIdleDetector = const UnsupportedUserIdleDetector(),
    bool? supportsTrayClickActions,
  }) {
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsUserIdleDetection: supportsUserIdleDetection,
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
      userIdleDetector: userIdleDetector,
      nativeLifecycleAdapter: isMacOS
          ? MethodChannelNativeLifecycleAdapter()
          : const UnsupportedNativeLifecycleAdapter(),
    );
  }

  final PlatformCapabilities capabilities;
  final StartupAtLoginAdapter startupAtLoginAdapter;
  final PowerEventAdapter powerEventAdapter;
  final UserIdleDetector userIdleDetector;
  final NativeLifecycleAdapter nativeLifecycleAdapter;
}
