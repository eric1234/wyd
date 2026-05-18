import 'dart:io';

import '../../application/application.dart';
import 'event_channel_power_event_adapter.dart';
import 'launch_at_startup_adapter.dart';
import 'method_channel_native_lifecycle_adapter.dart';
import 'system_idle_user_idle_detector.dart';

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
      isWindows: Platform.isWindows,
      supportsUserIdleDetection: userIdleDetector != null,
      userIdleDetector: userIdleDetector ?? const UnsupportedUserIdleDetector(),
    );
  }

  factory DesktopPlatformBindings.forPlatform({
    required bool isLinux,
    required bool isMacOS,
    bool isWindows = false,
    StartupAtLoginAdapter Function()? linuxStartupAtLoginFactory,
    StartupAtLoginAdapter Function()? macOSStartupAtLoginFactory,
    StartupAtLoginAdapter Function()? windowsStartupAtLoginFactory,
    bool supportsUserIdleDetection = false,
    UserIdleDetector userIdleDetector = const UnsupportedUserIdleDetector(),
    bool? supportsTrayClickActions,
  }) {
    final startupAtLoginAdapter = _startupAtLoginAdapterForPlatform(
      isLinux: isLinux,
      isMacOS: isMacOS,
      isWindows: isWindows,
      linuxStartupAtLoginFactory: linuxStartupAtLoginFactory,
      macOSStartupAtLoginFactory: macOSStartupAtLoginFactory,
      windowsStartupAtLoginFactory: windowsStartupAtLoginFactory,
    );
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsUserIdleDetection: supportsUserIdleDetection,
        supportsStartAtLogin:
            startupAtLoginAdapter is! UnsupportedStartupAtLoginAdapter,
        supportsPowerEvents: isMacOS,
        supportsTrayClickActions: supportsTrayClickActions ?? isMacOS,
      ),
      startupAtLoginAdapter: startupAtLoginAdapter,
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

  static StartupAtLoginAdapter _startupAtLoginAdapterForPlatform({
    required bool isLinux,
    required bool isMacOS,
    required bool isWindows,
    StartupAtLoginAdapter Function()? linuxStartupAtLoginFactory,
    StartupAtLoginAdapter Function()? macOSStartupAtLoginFactory,
    StartupAtLoginAdapter Function()? windowsStartupAtLoginFactory,
  }) {
    if (isLinux) {
      return linuxStartupAtLoginFactory?.call() ??
          LaunchAtStartupStartupAtLoginAdapter();
    }
    if (isMacOS) {
      return macOSStartupAtLoginFactory?.call() ??
          LaunchAtStartupStartupAtLoginAdapter();
    }
    if (isWindows) {
      return windowsStartupAtLoginFactory?.call() ??
          LaunchAtStartupStartupAtLoginAdapter();
    }
    return const UnsupportedStartupAtLoginAdapter();
  }
}
