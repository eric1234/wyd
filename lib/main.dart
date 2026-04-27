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

  await _runTrayApp();
}

Future<void> _runTrayApp() async {
  final database = await AppDatabase.openDefault();
  const clock = SystemClock();
  final trackerService = _trackerService(database, clock);
  final reportService = ReportService(
    transactions: SqliteTransactionRunner(database),
    clock: clock,
  );
  final settingsService = SettingsService(
    trackerService: trackerService,
    startupAtLoginAdapter: XdgAutostartStartupAtLoginAdapter(),
  );
  late final WydAppController controller;
  final nagScheduler = NagScheduler(
    clock: clock,
    timerFactory: const DartSchedulerTimerFactory(),
    typingActivityDetector: const UnsupportedTypingActivityDetector(),
    onShowPrompt: () => controller.showNagPrompt(),
    onPromptTimedOut: () => controller.nagPromptTimedOut(),
  );
  controller = WydAppController(
    trackerService: trackerService,
    trayAdapter: TrayManagerAdapter(),
    windowCoordinator: WindowCoordinator(
      DesktopMultiWindowAdapter(
        primaryWindowAdapter: SingleFlutterWindowAdapter(),
      ),
    ),
    nagScheduler: nagScheduler,
    singleInstanceAdapter: MethodChannelSingleInstanceAdapter(),
    powerEventAdapter: const UnsupportedPowerEventAdapter(),
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

Future<void> _runRoleWindow(
  WindowRole role,
  WindowController windowController, {
  required bool showOnReady,
}) async {
  final database = await AppDatabase.openDefault();
  const clock = SystemClock();
  final trackerService = _trackerService(database, clock);
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
      case 'configure':
        await windowConfigurator.apply(
          decodeRoleWindowConfiguration(call.arguments),
        );
      case 'showAndFocus':
        await windowConfigurator.showAndFocus();
      case 'ping':
        return ready;
      case 'close':
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
      await reportController.open();
    case WindowRole.settings:
      final settingsService = SettingsService(
        trackerService: trackerService,
        startupAtLoginAdapter: XdgAutostartStartupAtLoginAdapter(),
      );
      settingsController = SettingsController(
        client: settingsService,
        onSaved: (_) => _notifyMainWindowStateChanged(),
      );
      await settingsController.open();
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
        await windowConfigurator.showAndFocus();
      }
    }());
  });
}

TrackerService _trackerService(AppDatabase database, Clock clock) {
  return TrackerService(
    transactions: SqliteTransactionRunner(database),
    clock: clock,
    logger: const EnvironmentDiagnosticLogger(),
    capabilities: const PlatformCapabilities(
      supportsStartAtLogin: true,
      supportsTrayClickActions: true,
      supportsTrayRelativePositioning: false,
    ),
  );
}

Future<void> _notifyMainWindowStateChanged() async {
  try {
    await _mainWindowEventsChannel.invokeMethod<void>('stateChanged');
  } catch (_) {
    // The settings write is already persisted; notification only refreshes the
    // tray process' in-memory scheduler/menu snapshot.
  }
}
