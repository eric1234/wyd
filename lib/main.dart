import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
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

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

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

Future<void> _runTrayApp() async {
  if (!Platform.isLinux && !Platform.isMacOS) {
    throw UnsupportedError(
      'wyd currently supports Linux and macOS desktop only.',
    );
  }

  final database = await AppDatabase.openDefault();
  const clock = SystemClock();
  final platformBindings = DesktopPlatformBindings.current();
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
    typingActivityDetector: platformBindings.typingActivityDetector,
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
    hideResidentWindow: Platform.isMacOS
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
  final platformBindings = DesktopPlatformBindings.current();
  final trackerService = _trackerService(
    database,
    clock,
    platformBindings.capabilities,
  );
  final windowConfiguration = WindowRoleConfiguration.forRole(role);
  final windowConfigurator = DesktopWindowConfigurator();
  ReportController? reportController;
  SettingsController? settingsController;
  final closeHandler = HideOnCloseWindowHandler(
    onBeforeHide: role == WindowRole.settings
        ? () => settingsController?.commitChanges() ?? Future<void>.value()
        : null,
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
