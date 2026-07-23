import 'dart:io';

import '../../application/application.dart';
import 'gnome_idle_user_idle_detector.dart';
import 'launch_at_startup_adapter.dart';
import 'linux_dbus_power_event_adapter.dart';
import 'linux_logind_lifecycle_power_adapter.dart';
import 'method_channel_lifecycle_event_adapter.dart';
import 'screen_saver_idle_user_idle_detector.dart';
import 'system_idle_user_idle_detector.dart';

final class DesktopPlatformBindings {
  const DesktopPlatformBindings({
    required this.capabilities,
    required this.startupAtLoginAdapter,
    required this.lifecycleEventAdapter,
    required this.userIdleDetector,
  });

  static Future<DesktopPlatformBindings> current({
    DiagnosticLogger logger = const EnvironmentDiagnosticLogger(),
    bool includePowerLifecycleAdapters = true,
  }) async {
    final systemIdleDetector = await SystemIdleUserIdleDetector.create(
      logger: logger,
    );
    UserIdleDetector? userIdleDetector = systemIdleDetector;
    var idleBackend = userIdleDetector != null ? 'system_idle' : 'unsupported';

    if (userIdleDetector == null && Platform.isLinux) {
      final screenSaverIdleDetector =
          await ScreenSaverIdleUserIdleDetector.create(logger: logger);
      if (screenSaverIdleDetector != null) {
        userIdleDetector = screenSaverIdleDetector;
        idleBackend = 'screensaver dbus';
      }
    }

    if (userIdleDetector == null && Platform.isLinux) {
      final gnomeIdleDetector = await GnomeIdleUserIdleDetector.create(
        logger: logger,
      );
      if (gnomeIdleDetector != null) {
        userIdleDetector = gnomeIdleDetector;
        idleBackend = 'gnome mutter';
      }
    }

    LifecycleEventAdapter? linuxLifecycleEventAdapter;
    if (includePowerLifecycleAdapters && Platform.isLinux) {
      linuxLifecycleEventAdapter =
          await LinuxLogindLifecyclePowerAdapter.create(logger: logger) ??
          await LinuxDbusPowerEventAdapter.create(logger: logger);
    }
    logger.debug('idle detection backend selected: $idleBackend');
    return DesktopPlatformBindings.forPlatform(
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
      linuxLifecycleEventAdapterFactory: linuxLifecycleEventAdapter == null
          ? null
          : () => linuxLifecycleEventAdapter,
      includePowerLifecycleAdapters: includePowerLifecycleAdapters,
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
    LifecycleEventAdapter? Function()? linuxLifecycleEventAdapterFactory,
    LifecycleEventAdapter? Function()? macOSLifecycleEventAdapterFactory,
    bool includePowerLifecycleAdapters = true,
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
    final lifecycleEventAdapter = includePowerLifecycleAdapters
        ? _lifecycleEventAdapterForPlatform(
            isLinux: isLinux,
            isMacOS: isMacOS,
            isWindows: isWindows,
            linuxLifecycleEventAdapterFactory:
                linuxLifecycleEventAdapterFactory,
            macOSLifecycleEventAdapterFactory:
                macOSLifecycleEventAdapterFactory,
          )
        : const UnsupportedLifecycleEventAdapter();
    return DesktopPlatformBindings(
      capabilities: PlatformCapabilities(
        supportsUserIdleDetection: supportsUserIdleDetection,
        supportsStartAtLogin:
            startupAtLoginAdapter is! UnsupportedStartupAtLoginAdapter,
        supportsPowerEvents:
            lifecycleEventAdapter is! UnsupportedLifecycleEventAdapter,
        supportsTrayClickActions:
            supportsTrayClickActions ?? (isMacOS || isWindows),
      ),
      startupAtLoginAdapter: startupAtLoginAdapter,
      lifecycleEventAdapter: lifecycleEventAdapter,
      userIdleDetector: userIdleDetector,
    );
  }

  final PlatformCapabilities capabilities;
  final StartupAtLoginAdapter startupAtLoginAdapter;
  final LifecycleEventAdapter lifecycleEventAdapter;
  final UserIdleDetector userIdleDetector;

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

  static LifecycleEventAdapter _lifecycleEventAdapterForPlatform({
    required bool isLinux,
    required bool isMacOS,
    required bool isWindows,
    LifecycleEventAdapter? Function()? linuxLifecycleEventAdapterFactory,
    LifecycleEventAdapter? Function()? macOSLifecycleEventAdapterFactory,
  }) {
    if (isLinux) {
      return _lifecycleEventAdapterFromFactory(
        linuxLifecycleEventAdapterFactory,
      );
    }
    if (isMacOS) {
      return _lifecycleEventAdapterFromFactory(
        macOSLifecycleEventAdapterFactory ??
            () => const MethodChannelLifecycleEventAdapter(),
      );
    }
    if (isWindows) {
      return const MethodChannelLifecycleEventAdapter();
    }
    return const UnsupportedLifecycleEventAdapter();
  }

  static LifecycleEventAdapter _lifecycleEventAdapterFromFactory(
    LifecycleEventAdapter? Function()? factory,
  ) {
    if (factory == null) {
      return const UnsupportedLifecycleEventAdapter();
    }
    try {
      return factory() ?? const UnsupportedLifecycleEventAdapter();
    } catch (_) {
      return const UnsupportedLifecycleEventAdapter();
    }
  }
}
