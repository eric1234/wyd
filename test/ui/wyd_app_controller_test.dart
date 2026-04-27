import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';
import 'package:wyd/src/ui/wyd_app_controller.dart';

void main() {
  group('WydAppController', () {
    test('initializes tray menu from recovered state', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      await harness.controller.initialize();

      expect(harness.tray.initialized, isTrue);
      expect(harness.tray.latestEntries.last.action, TrayMenuAction.exit);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
    });

    test('surfaces startup error when tray initialization fails', () async {
      final harness = await _Harness.create(trayFailsOnInitialize: true);
      addTearDown(harness.dispose);

      await harness.controller.initialize();

      expect(harness.controller.startupError, contains('tray unavailable'));
      expect(harness.controller.activeRole, WindowRole.settings);
      expect(harness.window.openedRoles, contains(WindowRole.settings));
    });

    test('opens quick entry through controller and submits a task', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      final events = await harness.activityLog.allEvents();
      expect(events.single.eventType, ActivityEventType.startTask);
      expect(events.single.taskText, 'Write docs');
      expect(harness.window.closedRoles, contains(WindowRole.quickEntry));
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isTrue,
      );
    });

    test('second-instance activation opens quick entry', () async {
      final harness = await _Harness.create(withSingleInstance: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await harness.singleInstance.activateSecondInstance();

      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.window.openedRoles, contains(WindowRole.quickEntry));
    });

    test('active-task nag keeps a stable size for suggestions', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.controller.openQuickEntry();

      expect(harness.controller.quickEntry.state.suggestions, isEmpty);
      expect(
        harness.window.openedConfigurations.last.height,
        WindowRoleConfiguration.quickEntryHeight,
      );
      harness.window.resizedConfigurations.clear();

      await harness.controller.quickEntry.updateText('Write');
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.quickEntry.state.suggestions, isNotEmpty);
      expect(harness.window.resizedConfigurations, isEmpty);
    });

    test('warms report and settings windows after startup', () async {
      final harness = await _Harness.create(
        secondaryWindowWarmUpDelay: Duration.zero,
      );
      addTearDown(harness.dispose);

      await harness.controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(harness.window.preloadedRoles, [
        WindowRole.report,
        WindowRole.settings,
      ]);
      expect(harness.window.openedRoles, isEmpty);
    });

    test('opening a warmed report focuses the preloaded window', () async {
      final harness = await _Harness.create(
        secondaryWindowWarmUpDelay: Duration.zero,
      );
      addTearDown(harness.dispose);

      await harness.controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await harness.controller.openReport();

      expect(harness.window.openedRoles, isEmpty);
      expect(harness.window.focusedRoles, [WindowRole.report]);
    });

    test('routes tray stop action to service and refreshes menu', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      harness.tray.emitMenuAction(TrayMenuAction.stopTask);
      await Future<void>.delayed(Duration.zero);

      final events = await harness.activityLog.allEvents();
      expect(events.last.eventType, ActivityEventType.stopTask);
      expect(events.last.source, ActivitySource.manualStop);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
    });

    test(
      'opening quick entry while tracking schedules response timeout',
      () async {
        final harness = await _Harness.create(withScheduler: true);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();

        await harness.controller.openQuickEntry();

        expect(
          harness.controller.snapshot!.runtimeState.promptState.status,
          PromptStatus.visible,
        );
        expect(
          harness.timers.activeTimers.single.duration,
          const Duration(minutes: 1),
        );
      },
    );

    test(
      'scheduled timeout auto-stops task and keeps quick entry open',
      () async {
        final harness = await _Harness.create(withScheduler: true);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        await harness.controller.openQuickEntry();
        final shownAt = harness.clock.current;

        await harness.timers.fireFirst();

        final events = await harness.activityLog.allEvents();
        expect(events.last.eventType, ActivityEventType.stopTask);
        expect(events.last.source, ActivitySource.nagTimeout);
        expect(events.last.occurredAtUtc, shownAt);
        expect(harness.controller.quickEntry.state.isOpen, isTrue);
        expect(
          harness.controller.snapshot!.runtimeState.promptState.status,
          PromptStatus.expired,
        );
      },
    );

    test('nag prompt opens quick entry without overlaying report', () async {
      final harness = await _Harness.create(withScheduler: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      harness.window.openedRoles.clear();

      await harness.controller.openReport();
      await harness.controller.showNagPrompt();

      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntryOverlayVisible, isFalse);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.window.openedRoles, [
        WindowRole.report,
        WindowRole.quickEntry,
      ]);
    });

    test('report settings and nag can be open at the same time', () async {
      final harness = await _Harness.create(withScheduler: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.controller.openReport();
      await harness.controller.openSettings();
      await harness.controller.showNagPrompt();

      expect(harness.window.handles.keys, containsAll(WindowRole.values));
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
    });

    test('native close of quick entry keeps the tray app running', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await harness.controller.openQuickEntry();
      harness.window.emitCloseRequest(WindowRole.quickEntry);
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.activeRole, isNull);
      expect(harness.controller.quickEntry.state.isOpen, isFalse);
      expect(harness.exitRequests(), 0);
    });

    test('native close of report lets later nags open quick entry', () async {
      final harness = await _Harness.create(withScheduler: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      await harness.controller.openReport();

      harness.window.emitCloseRequest(WindowRole.report);
      await Future<void>.delayed(Duration.zero);
      await harness.controller.showNagPrompt();

      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntryOverlayVisible, isFalse);
      expect(harness.window.openedRoles.last, WindowRole.quickEntry);
      expect(harness.exitRequests(), 0);
    });

    test(
      'exit does not force-close child windows before process exit',
      () async {
        final harness = await _Harness.create(withScheduler: true);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        await harness.controller.openReport();
        await harness.controller.openSettings();
        await harness.controller.showNagPrompt();
        harness.window.closedRoles.clear();

        await harness.controller.exitRequested();

        expect(harness.exitRequests(), 1);
        expect(harness.window.closedRoles, isEmpty);
        expect(harness.controller.quickEntry.state.isOpen, isFalse);
        final events = await harness.activityLog.allEvents();
        expect(events.last.source, ActivitySource.exit);
      },
    );

    test(
      'submitting nag closes quick entry without altering report window',
      () async {
        final harness = await _Harness.create(withScheduler: true);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        await harness.controller.openReport();
        await harness.controller.showNagPrompt();

        await harness.controller.quickEntry.updateText('Fix bug');
        await harness.controller.quickEntry.submit();

        final events = await harness.activityLog.allEvents();
        expect(events.map((event) => event.eventType), [
          ActivityEventType.startTask,
          ActivityEventType.switchTask,
        ]);
        expect(harness.controller.activeRole, isNull);
        expect(harness.controller.quickEntryOverlayVisible, isFalse);
        expect(harness.window.closedRoles, contains(WindowRole.quickEntry));
      },
    );

    test('lock event stops an active task with system lock source', () async {
      final harness = await _Harness.create(withScheduler: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.controller.handlePowerEvent(PowerEvent.lock);

      final events = await harness.activityLog.allEvents();
      expect(events.last.eventType, ActivityEventType.stopTask);
      expect(events.last.source, ActivitySource.systemLock);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
      expect(harness.timers.activeTimers, isEmpty);
    });

    test('sleep event stops active task and dismisses quick entry', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      await harness.controller.openQuickEntry();

      await harness.controller.handlePowerEvent(PowerEvent.sleep);

      final events = await harness.activityLog.allEvents();
      expect(events.last.source, ActivitySource.systemSleep);
      expect(harness.controller.quickEntry.state.isOpen, isFalse);
      expect(harness.window.closedRoles, contains(WindowRole.quickEntry));
    });

    test('power event while idle does not append a stop event', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await harness.controller.handlePowerEvent(PowerEvent.lock);

      expect(await harness.activityLog.allEvents(), isEmpty);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
    });
  });
}

final class _Harness {
  _Harness({
    required this.database,
    required this.activityLog,
    required this.tray,
    required this.window,
    required this.clock,
    required this.timers,
    required this.singleInstance,
    required this.controller,
    required this.exitRequests,
  });

  final AppDatabase database;
  final SqliteActivityLogRepository activityLog;
  final _FakeTrayAdapter tray;
  final _FakeWindowAdapter window;
  final _FakeClock clock;
  final _FakeSchedulerTimerFactory timers;
  final _FakeSingleInstanceAdapter singleInstance;
  final WydAppController controller;
  final int Function() exitRequests;

  static Future<_Harness> create({
    bool withScheduler = false,
    bool withSingleInstance = false,
    bool trayFailsOnInitialize = false,
    Duration? secondaryWindowWarmUpDelay,
  }) async {
    final database = await AppDatabase.openInMemory(
      databaseFactory: databaseFactoryFfi,
    );
    final clock = _FakeClock(DateTime.utc(2026, 1, 1, 9));
    final service = TrackerService(
      transactions: SqliteTransactionRunner(database),
      clock: clock,
    );
    final tray = _FakeTrayAdapter(failsOnInitialize: trayFailsOnInitialize);
    final window = _FakeWindowAdapter();
    final timers = _FakeSchedulerTimerFactory();
    final singleInstance = _FakeSingleInstanceAdapter();
    var exitRequests = 0;
    late final WydAppController controller;
    final scheduler = withScheduler
        ? NagScheduler(
            clock: clock,
            timerFactory: timers,
            typingActivityDetector: const UnsupportedTypingActivityDetector(),
            onShowPrompt: () => controller.showNagPrompt(),
            onPromptTimedOut: () => controller.nagPromptTimedOut(),
          )
        : null;
    controller = WydAppController(
      trackerService: service,
      trayAdapter: tray,
      windowCoordinator: WindowCoordinator(window),
      nagScheduler: scheduler,
      singleInstanceAdapter: withSingleInstance ? singleInstance : null,
      secondaryWindowWarmUpDelay: secondaryWindowWarmUpDelay,
      onExit: () async {
        exitRequests += 1;
      },
    );

    return _Harness(
      database: database,
      activityLog: SqliteActivityLogRepository(database.database),
      tray: tray,
      window: window,
      clock: clock,
      timers: timers,
      singleInstance: singleInstance,
      controller: controller,
      exitRequests: () => exitRequests,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await tray.dispose();
    await window.dispose();
    await database.close();
  }
}

final class _FakeSingleInstanceAdapter implements SingleInstanceAdapter {
  Future<void> Function()? _onSecondInstanceActivated;

  @override
  Future<void> initialize(
    Future<void> Function() onSecondInstanceActivated,
  ) async {
    _onSecondInstanceActivated = onSecondInstanceActivated;
  }

  Future<void> activateSecondInstance() async {
    await _onSecondInstanceActivated?.call();
  }
}

final class _FakeClock implements Clock {
  _FakeClock(this.current);

  DateTime current;

  @override
  DateTime nowUtc() => current;
}

final class _FakeSchedulerTimerFactory implements SchedulerTimerFactory {
  final List<_FakeSchedulerTimer> timers = [];

  List<_FakeSchedulerTimer> get activeTimers {
    return timers.where((timer) => timer.isActive).toList();
  }

  @override
  SchedulerTimer schedule(Duration duration, void Function() callback) {
    final timer = _FakeSchedulerTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  Future<void> fireFirst() async {
    activeTimers.first.fire();
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeSchedulerTimer implements SchedulerTimer {
  _FakeSchedulerTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _callback();
  }
}

final class _FakeTrayAdapter implements TrayAdapter {
  _FakeTrayAdapter({this.failsOnInitialize = false});

  final bool failsOnInitialize;
  final StreamController<TrayMenuAction> _menuActions =
      StreamController<TrayMenuAction>.broadcast();
  final StreamController<void> _primaryClicks =
      StreamController<void>.broadcast();
  bool initialized = false;
  List<TrayMenuEntry> latestEntries = const [];

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(List<TrayMenuEntry> entries) async {
    if (failsOnInitialize) {
      throw StateError('tray unavailable');
    }
    initialized = true;
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
  final List<WindowRoleConfiguration> openedConfigurations = [];
  final List<WindowRole> openedRoles = [];
  final List<WindowRole> preloadedRoles = [];
  final List<WindowRole> focusedRoles = [];
  final List<WindowRoleConfiguration> resizedConfigurations = [];
  final List<WindowRole> closedRoles = [];
  final StreamController<WindowHandle> _closeRequests =
      StreamController<WindowHandle>.broadcast();

  @override
  Stream<WindowHandle> get closeRequests => _closeRequests.stream;

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async {
    openedConfigurations.add(configuration);
    openedRoles.add(configuration.role);
    final handle = WindowHandle(configuration.role.name);
    handles[configuration.role] = handle;
    return handle;
  }

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) async {
    preloadedRoles.add(configuration.role);
    final handle = WindowHandle(configuration.role.name);
    handles[configuration.role] = handle;
    return handle;
  }

  @override
  Future<bool> isOpen(WindowHandle handle) async {
    return handles.values.any((candidate) => candidate.id == handle.id);
  }

  @override
  Future<void> focus(WindowHandle handle) async {
    final role = WindowRole.values.singleWhere(
      (role) => role.name == handle.id,
    );
    focusedRoles.add(role);
  }

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) async {
    resizedConfigurations.add(configuration);
  }

  @override
  Future<void> close(WindowHandle handle) async {
    final role = WindowRole.values.singleWhere(
      (role) => role.name == handle.id,
    );
    closedRoles.add(role);
    handles.remove(role);
  }

  void emitCloseRequest(WindowRole role) {
    final handle = handles.remove(role);
    if (handle != null) {
      _closeRequests.add(handle);
    }
  }

  Future<void> dispose() async {
    await _closeRequests.close();
  }
}
