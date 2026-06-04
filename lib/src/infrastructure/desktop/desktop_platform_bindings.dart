import 'dart:io';

import '../../application/application.dart';
import 'desktop_screen_state_power_event_adapter.dart';
import 'gnome_idle_user_idle_detector.dart';
import 'launch_at_startup_adapter.dart';
import 'linux_dbus_power_event_adapter.dart';
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

  static Future<DesktopPlatformBindings> current({
    DiagnosticLogger logger = const EnvironmentDiagnosticLogger(),
  }) async {
    final systemIdleDetector = await SystemIdleUserIdleDetector.create(
      logger: logger,
    );
    final userIdleDetector =
        systemIdleDetector ??
        (Platform.isLinux
            ? await GnomeIdleUserIdleDetector.create(logger: logger)
            : null);
    final linuxPowerEventAdapter = Platform.isLinux
        ? await LinuxDbusPowerEventAdapter.create(logger: logger)
        : null;
    logger.debug(
      'idle detection capability: ${userIdleDetector != null ? 'supported' : 'unsupported'}',
    );
    return DesktopPlatformBindings.forPlatform(
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
      linuxPowerEventAdapterFactory: linuxPowerEventAdapter == null
          ? null
          : () => linuxPowerEventAdapter,
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
    PowerEventAdapter? Function()? linuxPowerEventAdapterFactory,
    PowerEventAdapter? Function()? macOSPowerEventAdapterFactory,
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
    final powerEventAdapter = _powerEventAdapterForPlatform(
      isLinux: isLinux,
      isMacOS: isMacOS,
      isWindows: isWindows,
      linuxPowerEventAdapterFactory: linuxPowerEventAdapterFactory,
      macOSPowerEventAdapterFactory: macOSPowerEventAdapterFactory,
    );
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsUserIdleDetection: supportsUserIdleDetection,
        supportsStartAtLogin:
            startupAtLoginAdapter is! UnsupportedStartupAtLoginAdapter,
        supportsPowerEvents: powerEventAdapter is! UnsupportedPowerEventAdapter,
        supportsTrayClickActions: supportsTrayClickActions ?? isMacOS,
      ),
      startupAtLoginAdapter: startupAtLoginAdapter,
      powerEventAdapter: powerEventAdapter,
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

  static PowerEventAdapter _powerEventAdapterForPlatform({
    required bool isLinux,
    required bool isMacOS,
    required bool isWindows,
    PowerEventAdapter? Function()? linuxPowerEventAdapterFactory,
    PowerEventAdapter? Function()? macOSPowerEventAdapterFactory,
  }) {
    if (isLinux) {
      return _powerEventAdapterFromFactory(linuxPowerEventAdapterFactory);
    }
    if (isMacOS) {
      return _powerEventAdapterFromFactory(
        macOSPowerEventAdapterFactory ??
            () => DesktopScreenStatePowerEventAdapter(),
      );
    }
    if (isWindows) {
      return const UnsupportedPowerEventAdapter();
    }
    return const UnsupportedPowerEventAdapter();
  }

  static PowerEventAdapter _powerEventAdapterFromFactory(
    PowerEventAdapter? Function()? factory,
  ) {
    if (factory == null) {
      return const UnsupportedPowerEventAdapter();
    }
    try {
      return factory() ?? const UnsupportedPowerEventAdapter();
    } catch (_) {
      return const UnsupportedPowerEventAdapter();
    }
  }
}
