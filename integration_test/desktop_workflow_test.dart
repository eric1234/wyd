import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';
import 'package:wyd/src/ui/report/report.dart';
import 'package:wyd/src/ui/settings/settings.dart';
import 'package:wyd/src/ui/wyd_app.dart';
import 'package:wyd/src/ui/wyd_app_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs core desktop workflow with fake platform adapters', (
    tester,
  ) async {
    final harness = await _IntegrationHarness.create();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    await tester.pumpWidget(WydApp(controller: harness.controller));
    await _pumpFrames(tester);

    await harness.controller.openQuickEntry();
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField), 'Write docs');
    await _pumpFrames(tester);
    await tester.tap(find.text('Submit'));
    await _pumpFrames(tester);

    harness.clock.current = DateTime.utc(2026, 1, 2, 9, 15);
    await harness.controller.openQuickEntry();
    await _pumpFrames(tester);
    await tester.tap(find.text('Submit'));
    await _pumpFrames(tester);

    harness.clock.current = DateTime.utc(2026, 1, 2, 9, 30);
    await harness.controller.openQuickEntry();
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField), 'Fix bug');
    await _pumpFrames(tester);
    await tester.tap(find.text('Submit'));
    await _pumpFrames(tester);

    harness.clock.current = DateTime.utc(2026, 1, 2, 10);
    harness.tray.emitMenuAction(TrayMenuAction.stopTask);
    await _pumpFrames(tester);

    final events = await harness.activityLog.allEvents();
    expect(events.map((event) => event.eventType), [
      ActivityEventType.startTask,
      ActivityEventType.switchTask,
      ActivityEventType.stopTask,
    ]);
    expect(events[0].taskText, 'Write docs');
    expect(events[1].taskText, 'Fix bug');
    expect(events[2].source, ActivitySource.manualStop);

    await harness.controller.openReport();
    await _pumpFrames(tester);
    expect(harness.window.handles.keys, contains(WindowRole.report));
    expect(find.text('Total: 1h'), findsNothing);

    await harness.controller.openSettings();
    await _pumpFrames(tester);
    expect(harness.window.handles.keys, contains(WindowRole.report));
    expect(harness.window.handles.keys, contains(WindowRole.settings));
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('recovers active task after unclean shutdown state', (
    tester,
  ) async {
    final harness = await _IntegrationHarness.create();
    addTearDown(harness.dispose);
    await harness.activityLog.append(
      ActivityLogEvent.startTask(
        occurredAtUtc: DateTime.utc(2026, 1, 2, 9),
        taskText: 'Recovered task',
      ),
    );
    await harness.runtimeState.save(
      RuntimeState(
        lastConfirmationAtUtc: DateTime.utc(2026, 1, 2, 9, 15),
        cleanShutdown: false,
      ),
    );

    await harness.controller.initialize();
    await tester.pumpWidget(WydApp(controller: harness.controller));
    await _pumpFrames(tester);

    final events = await harness.activityLog.allEvents();
    expect(events.map((event) => event.eventType), [
      ActivityEventType.startTask,
      ActivityEventType.stopTask,
    ]);
    expect(events.last.source, ActivitySource.recovery);
    expect(events.last.occurredAtUtc, DateTime.utc(2026, 1, 2, 9, 15));
    expect(harness.controller.snapshot!.activeTask, isNull);
  });

  testWidgets('shows nag prompt in separate quick-entry window', (
    tester,
  ) async {
    final harness = await _IntegrationHarness.create();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    await tester.pumpWidget(WydApp(controller: harness.controller));
    await _pumpFrames(tester);

    await harness.controller.openQuickEntry();
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField), 'Write docs');
    await _pumpFrames(tester);
    await tester.tap(find.text('Submit'));
    await _pumpFrames(tester);

    harness.clock.current = DateTime.utc(2026, 1, 2, 9, 30);
    await harness.controller.openReport();
    await _pumpFrames(tester);
    expect(harness.window.handles.keys, contains(WindowRole.report));
    expect(find.text('Report'), findsNothing);

    await harness.controller.showNagPrompt();
    await _pumpFrames(tester);

    expect(harness.controller.activeRole, WindowRole.quickEntry);
    expect(harness.window.handles.keys, contains(WindowRole.report));
    expect(harness.window.handles.keys, contains(WindowRole.quickEntry));
    expect(find.byType(TextField), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

final class _IntegrationHarness {
  _IntegrationHarness({
    required this.tempDirectory,
    required this.database,
    required this.activityLog,
    required this.runtimeState,
    required this.settings,
    required this.clock,
    required this.tray,
    required this.window,
    required this.controller,
  });

  final Directory tempDirectory;
  final AppDatabase database;
  final SqliteActivityLogRepository activityLog;
  final SqliteRuntimeStateRepository runtimeState;
  final SqliteSettingsRepository settings;
  final _FakeClock clock;
  final _FakeTrayAdapter tray;
  final _FakeWindowAdapter window;
  final WydAppController controller;

  static Future<_IntegrationHarness> create() async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'wyd_workflow_',
    );
    final database = await AppDatabase.openAtPath(
      p.join(tempDirectory.path, 'wyd.sqlite'),
    );
    final clock = _FakeClock(DateTime.utc(2026, 1, 2, 9));
    final trackerService = TrackerService(
      transactions: SqliteTransactionRunner(database),
      clock: clock,
      capabilities: const PlatformCapabilities(supportsTrayClickActions: true),
    );
    final reportService = ReportService(
      transactions: SqliteTransactionRunner(database),
      clock: clock,
    );
    final settingsService = SettingsService(
      trackerService: trackerService,
      startupAtLoginAdapter: const UnsupportedStartupAtLoginAdapter(),
    );
    final tray = _FakeTrayAdapter();
    final window = _FakeWindowAdapter();
    late final WydAppController controller;
    controller = WydAppController(
      trackerService: trackerService,
      trayAdapter: tray,
      windowCoordinator: WindowCoordinator(window),
      reportController: ReportController(reportService),
      settingsController: SettingsController(
        client: settingsService,
        onSaved: (snapshot) => controller.settingsSaved(snapshot),
      ),
      onExit: () async {},
    );

    return _IntegrationHarness(
      tempDirectory: tempDirectory,
      database: database,
      activityLog: SqliteActivityLogRepository(database.database),
      runtimeState: SqliteRuntimeStateRepository(database.database),
      settings: SqliteSettingsRepository(database.database),
      clock: clock,
      tray: tray,
      window: window,
      controller: controller,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await tray.dispose();
    await database.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

final class _FakeClock implements Clock {
  _FakeClock(this.current);

  DateTime current;

  @override
  DateTime nowUtc() => current;
}

final class _FakeTrayAdapter implements TrayAdapter {
  final StreamController<TrayMenuAction> _menuActions =
      StreamController<TrayMenuAction>.broadcast();
  final StreamController<void> _primaryClicks =
      StreamController<void>.broadcast();
  List<TrayMenuEntry> latestEntries = const [];

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(List<TrayMenuEntry> entries) async {
    latestEntries = entries;
  }

  @override
  Future<void> updateMenu(List<TrayMenuEntry> entries) async {
    latestEntries = entries;
  }

  void emitMenuAction(TrayMenuAction action) {
    _menuActions.add(action);
  }

  @override
  Future<void> dispose() async {
    await _menuActions.close();
    await _primaryClicks.close();
  }
}

final class _FakeWindowAdapter implements WindowAdapter {
  final Map<WindowRole, WindowHandle> handles = {};

  @override
  Stream<WindowHandle> get closeRequests => const Stream.empty();

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async {
    final handle = WindowHandle(configuration.role.name);
    handles[configuration.role] = handle;
    return handle;
  }

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) async {
    return open(configuration);
  }

  @override
  Future<bool> isOpen(WindowHandle handle) async {
    return handles.values.any((candidate) => candidate.id == handle.id);
  }

  @override
  Future<void> focus(WindowHandle handle) async {}

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) async {}

  @override
  Future<void> close(WindowHandle handle) async {
    handles.removeWhere((role, candidate) => candidate.id == handle.id);
  }
}
