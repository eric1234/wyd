import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'src/application/application.dart';
import 'src/infrastructure/desktop/desktop.dart';
import 'src/infrastructure/persistence/persistence.dart';
import 'src/ui/report/report.dart';
import 'src/ui/settings/settings.dart';
import 'src/ui/wyd_app.dart';
import 'src/ui/wyd_app_controller.dart';

const _mainWindowEventsChannel = WindowMethodChannel(
  'wyd/main_window_events',
  mode: ChannelMode.unidirectional,
);
const _clearDataFlag = '--clear-data';
const _clearDataDebugExitDelay = Duration(seconds: 2);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.contains(_clearDataFlag)) {
    await _clearDataAndExit();
    return;
  }

  final currentWindow = await WindowController.fromCurrentEngine();
  final childWindowRole = decodeRoleWindowRole(currentWindow.arguments);
  if (childWindowRole != null) {
    await _runRoleWindow(
      childWindowRole,
      currentWindow,
      showOnReady: decodeRoleWindowShowOnReady(currentWindow.arguments),
    );
    return;
  }

  try {
    await _runTrayApp();
  } catch (error) {
    await _runFatalStartupApp(error);
  }
}

Future<void> _clearDataAndExit() async {
  try {
    final databasePath = await AppDatabase.defaultDatabasePath();
    await AppDatabase.deleteDatabaseFiles(databasePath);
    stdout.writeln('Cleared wyd data.');
    await stdout.flush();
    await _waitForDebugToolingBeforeExit();
    exit(0);
  } catch (error) {
    stderr.writeln('Failed to clear wyd data: $error');
    await stderr.flush();
    await _waitForDebugToolingBeforeExit();
    exit(1);
  }
}

Future<void> _waitForDebugToolingBeforeExit() async {
  if (kReleaseMode) {
    return;
  }

  await Future<void>.delayed(_clearDataDebugExitDelay);
}

Future<void> _runTrayApp() async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    throw UnsupportedError(
      'wyd currently supports Linux, macOS, and Windows desktop only.',
    );
  }

  final database = await AppDatabase.openDefault();
  const clock = SystemClock();
  final platformBindings = await DesktopPlatformBindings.current();
  final trackerService = _trackerService(
    database,
    clock,
    platformBindings.capabilities,
  );
  final reportService = ReportService(
    transactions: SqliteTransactionRunner(database),
    clock: clock,
  );
  final settingsService = SettingsService(
    trackerService: trackerService,
    startupAtLoginAdapter: platformBindings.startupAtLoginAdapter,
  );
  final primaryWindowAdapter = SingleFlutterWindowAdapter();
  late final WydAppController controller;
  final nagScheduler = NagScheduler(
    clock: clock,
    timerFactory: const DartSchedulerTimerFactory(),
    userIdleDetector: platformBindings.userIdleDetector,
    onShowPrompt: () => controller.showNagPrompt(),
    onPromptTimedOut: () => controller.nagPromptTimedOut(),
    onError: (error, stackTrace) =>
        unawaited(controller.handleRuntimeError(error, stackTrace)),
  );
  controller = WydAppController(
    trackerService: trackerService,
    trayAdapter: TrayManagerAdapter(),
    windowCoordinator: WindowCoordinator(
      DesktopMultiWindowAdapter(primaryWindowAdapter: primaryWindowAdapter),
    ),
    nagScheduler: nagScheduler,
    singleInstanceAdapter: MethodChannelSingleInstanceAdapter(),
    powerEventAdapter: platformBindings.powerEventAdapter,
    nativeLifecycleAdapter: platformBindings.nativeLifecycleAdapter,
    startupAtLoginReconciler: settingsService.reconcileStartAtLogin,
    hideResidentWindow: Platform.isMacOS || Platform.isWindows
        ? primaryWindowAdapter.hideResidentWindow
        : null,
    reportController: ReportController(reportService),
    settingsController: SettingsController(
      client: settingsService,
      onSaved: (snapshot) => controller.settingsSaved(snapshot),
    ),
    onExit: () async {
      await database.close();
      exit(0);
    },
  );
  await _mainWindowEventsChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'stateChanged':
        await controller.refreshFromExternalChange();
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  });

  runApp(WydApp(controller: controller));
}

Future<void> _runFatalStartupApp(Object error) async {
  runApp(WydFatalStartupApp(message: error.toString(), onExit: () => exit(1)));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      try {
        await windowManager.ensureInitialized();
        final configurator = DesktopWindowConfigurator();
        await windowManager.waitUntilReadyToShow();
        await configurator.apply(WindowRoleConfiguration.startupError());
        await configurator.showAndFocus();
      } catch (_) {
        exit(1);
      }
    }());
  });
}

Future<void> _runRoleWindow(
  WindowRole role,
  WindowController windowController, {
  required bool showOnReady,
}) async {
  final database = await AppDatabase.openDefault();
  const clock = SystemClock();
  final platformBindings = await DesktopPlatformBindings.current();
  final trackerService = _trackerService(
    database,
    clock,
    platformBindings.capabilities,
  );
  final windowConfiguration = WindowRoleConfiguration.forRole(role);
  final windowConfigurator = DesktopWindowConfigurator(
    windowAttentionAdapter: const MethodChannelLinuxWindowAttentionAdapter(),
  );
  ReportController? reportController;
  SettingsController? settingsController;
  final closeHandler = HideOnCloseWindowHandler(
    onBeforeHide: () => _handleRoleWindowBeforeHide(
      role,
      reportController: reportController,
      settingsController: settingsController,
    ),
  );
  var ready = false;

  await windowManager.ensureInitialized();
  await closeHandler.initialize();
  await windowController.setWindowMethodHandler((call) async {
    switch (call.method) {
      case RoleWindowProtocol.configureMethod:
        await windowConfigurator.apply(
          decodeRoleWindowConfiguration(call.arguments),
        );
      case RoleWindowProtocol.showAndFocusMethod:
        _refreshRoleForShow(
          role,
          reportController: reportController,
          settingsController: settingsController,
        );
        await windowConfigurator.showAndFocus();
      case RoleWindowProtocol.pingMethod:
        return ready;
      case RoleWindowProtocol.closeMethod:
        await settingsController?.close();
        await database.close();
        await closeHandler.forceClose();
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
  });

  switch (role) {
    case WindowRole.report:
      final reportService = ReportService(
        transactions: SqliteTransactionRunner(database),
        clock: clock,
      );
      reportController = ReportController(reportService);
    case WindowRole.settings:
      final settingsService = SettingsService(
        trackerService: trackerService,
        startupAtLoginAdapter: platformBindings.startupAtLoginAdapter,
      );
      settingsController = SettingsController(
        client: settingsService,
        onSaved: (_) => _notifyMainWindowStateChanged(),
      );
    case WindowRole.quickEntry:
      break;
  }

  runApp(
    WydChildWindowApp(
      role: role,
      reportController: reportController,
      settingsController: settingsController,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      await windowManager.waitUntilReadyToShow();
      await windowConfigurator.apply(windowConfiguration);
      ready = true;
      if (showOnReady) {
        _refreshRoleForShow(
          role,
          reportController: reportController,
          settingsController: settingsController,
        );
        await windowConfigurator.showAndFocus();
      }
    }());
  });
}

void _refreshRoleForShow(
  WindowRole role, {
  required ReportController? reportController,
  required SettingsController? settingsController,
}) {
  switch (role) {
    case WindowRole.report:
      reportController?.refreshForShow();
    case WindowRole.settings:
      settingsController?.refreshForShow();
    case WindowRole.quickEntry:
      break;
  }
}

Future<void> _handleRoleWindowBeforeHide(
  WindowRole role, {
  required ReportController? reportController,
  required SettingsController? settingsController,
}) async {
  switch (role) {
    case WindowRole.report:
      reportController?.close();
    case WindowRole.settings:
      await settingsController?.commitChanges();
    case WindowRole.quickEntry:
      break;
  }
}

TrackerService _trackerService(
  AppDatabase database,
  Clock clock,
  PlatformCapabilities capabilities,
) {
  return TrackerService(
    transactions: SqliteTransactionRunner(database),
    clock: clock,
    logger: const EnvironmentDiagnosticLogger(),
    capabilities: capabilities,
  );
}

Future<void> _notifyMainWindowStateChanged() async {
  try {
    await _mainWindowEventsChannel.invokeMethod<void>('stateChanged');
  } catch (error) {
    throw StateError(
      'Settings were saved, but the tray process did not refresh: $error',
    );
  }
}
