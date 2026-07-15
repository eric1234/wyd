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
      expect(harness.tray.initializedIconStatus, TrayIconStatus.idle);
      expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
      expect(harness.tray.initializedTooltip, 'No current task');
      expect(harness.tray.latestTooltip, 'No current task');
      expect(harness.tray.latestEntries.map((entry) => entry.action), [
        TrayMenuAction.updateTask,
        TrayMenuAction.stopTask,
        TrayMenuAction.report,
        TrayMenuAction.settings,
        TrayMenuAction.about,
        TrayMenuAction.exit,
      ]);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
    });

    test('hides the resident primary window after startup', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      await harness.controller.initialize();

      expect(harness.hideResidentWindowRequests(), 1);
    });

    test('auto-opens quick entry after startup', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      await harness.controller.initialize();

      expect(harness.tray.initialized, isTrue);
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.window.openedRoles, [WindowRole.quickEntry]);
      expect(
        harness.controller.snapshot!.runtimeState.promptState.status,
        PromptStatus.none,
      );
    });

    test('surfaces startup error when tray initialization fails', () async {
      final harness = await _Harness.create(trayFailsOnInitialize: true);
      addTearDown(harness.dispose);

      await harness.controller.initialize();

      expect(harness.controller.startupError, contains('tray unavailable'));
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.window.openedRoles, contains(WindowRole.quickEntry));
      expect(
        harness.window.openedConfigurations.last.title,
        'wyd startup error',
      );
      expect(harness.hideResidentWindowRequests(), 1);
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
      expect(harness.tray.latestIconStatus, TrayIconStatus.tracking);
      expect(harness.tray.latestTooltip, 'Write docs');
    });

    test('second-instance activation reopens quick entry', () async {
      final harness = await _Harness.create(withSingleInstance: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      harness.window.emitCloseRequest(WindowRole.quickEntry);
      await Future<void>.delayed(Duration.zero);

      await harness.singleInstance.activateSecondInstance();

      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.window.openedRoles.last, WindowRole.quickEntry);
    });

    test('active-task nag keeps a stable size for suggestions', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.controller.openQuickEntry();

      expect(harness.controller.quickEntry.state.suggestions, isNotEmpty);
      expect(harness.controller.quickEntry.state.highlightedIndex, isNull);
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
      expect(harness.window.openedRoles, [WindowRole.quickEntry]);
    });

    test('opening a warmed report focuses the preloaded window', () async {
      final harness = await _Harness.create(
        secondaryWindowWarmUpDelay: Duration.zero,
      );
      addTearDown(harness.dispose);

      await harness.controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await harness.controller.openReport();

      expect(harness.window.openedRoles, [WindowRole.quickEntry]);
      expect(harness.window.focusedRoles, [WindowRole.report]);
    });

    test('tray about opens the about window', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      harness.window.openedRoles.clear();

      harness.tray.emitMenuAction(TrayMenuAction.about);
      await _waitUntil(
        () => harness.window.openedRoles.contains(WindowRole.about),
      );

      expect(harness.window.openedRoles, [WindowRole.about]);
      expect(harness.window.openedConfigurations.last.title, 'About wyd');
      expect(harness.window.openedConfigurations.last.resizable, isFalse);
      expect(harness.controller.activeRole, WindowRole.quickEntry);
    });

    test('tray stop stops task and opens quick entry reminder', () async {
      final harness = await _Harness.create(withScheduler: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      harness.window.openedRoles.clear();

      harness.tray.emitMenuAction(TrayMenuAction.stopTask);
      await _waitUntil(() => harness.window.openedRoles.isNotEmpty);

      final events = await harness.activityLog.allEvents();
      expect(events.last.eventType, ActivityEventType.stopTask);
      expect(events.last.source, ActivitySource.manualStop);
      expect(
        harness.tray.latestEntries
            .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
            .enabled,
        isFalse,
      );
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.controller.quickEntry.state.text, isEmpty);
      expect(harness.controller.snapshot!.activeTask, isNull);
      expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
      expect(harness.tray.latestTooltip, 'No current task');
      expect(
        harness.controller.snapshot!.runtimeState.promptState.status,
        PromptStatus.none,
      );
      expect(harness.timers.activeTimers, isEmpty);
      expect(harness.window.openedRoles, [WindowRole.quickEntry]);
    });

    test(
      'stop while quick entry is open resets text and keeps window',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        await harness.controller.openQuickEntry();
        expect(harness.controller.quickEntry.state.text, 'Write docs');
        harness.window.closedRoles.clear();
        harness.window.openedRoles.clear();
        harness.window.focusedRoles.clear();

        await harness.controller.stopTask();

        final events = await harness.activityLog.allEvents();
        expect(events.last.eventType, ActivityEventType.stopTask);
        expect(events.last.source, ActivitySource.manualStop);
        expect(harness.controller.activeRole, WindowRole.quickEntry);
        expect(harness.controller.quickEntry.state.isOpen, isTrue);
        expect(harness.controller.quickEntry.state.text, isEmpty);
        expect(
          harness.controller.snapshot!.runtimeState.promptState.status,
          PromptStatus.none,
        );
        expect(harness.window.closedRoles, isEmpty);
        expect(harness.window.openedRoles, isEmpty);
        expect(harness.window.focusedRoles, [WindowRole.quickEntry]);
        expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
        expect(harness.tray.latestTooltip, 'No current task');
      },
    );

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
      'startup nag for recovered active task schedules response timeout',
      () async {
        final harness = await _Harness.create(withScheduler: true);
        addTearDown(harness.dispose);
        await harness.activityLog.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: harness.clock.current,
            taskText: 'Write docs',
          ),
        );

        await harness.controller.initialize();

        expect(harness.controller.activeRole, WindowRole.quickEntry);
        expect(harness.controller.quickEntry.state.isOpen, isTrue);
        expect(harness.controller.quickEntry.state.text, 'Write docs');
        expect(
          harness.controller.snapshot!.runtimeState.promptState.status,
          PromptStatus.visible,
        );
        expect(harness.tray.initializedIconStatus, TrayIconStatus.tracking);
        expect(harness.tray.latestIconStatus, TrayIconStatus.tracking);
        expect(harness.tray.initializedTooltip, 'Write docs');
        expect(harness.tray.latestTooltip, 'Write docs');
        expect(
          harness.timers.activeTimers.single.duration,
          const Duration(minutes: 1),
        );
      },
    );

    test('failed quick-entry show does not persist a phantom prompt', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      harness.window.failingOpenRoles.add(WindowRole.quickEntry);

      await expectLater(
        () => harness.controller.openQuickEntry(),
        throwsStateError,
      );

      final runtimeState = await SqliteRuntimeStateRepository(
        harness.database.database,
      ).read();
      expect(runtimeState.promptState.status, PromptStatus.none);
      expect(harness.controller.quickEntry.state.isOpen, isFalse);
      expect(harness.controller.activeRole, isNull);
    });

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

      expect(
        harness.window.handles.keys,
        containsAll([
          WindowRole.quickEntry,
          WindowRole.report,
          WindowRole.settings,
        ]),
      );
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

    test('native termination request follows graceful exit path', () async {
      final harness = await _Harness.create(withNativeLifecycle: true);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.nativeLifecycle.requestTermination();

      expect(harness.exitRequests(), 1);
      final events = await harness.activityLog.allEvents();
      expect(events.last.source, ActivitySource.exit);
    });

    test(
      'initializes acknowledged power adapter without subscribing to stream',
      () async {
        final powerEvents = _FakeAcknowledgedPowerEventAdapter();
        final harness = await _Harness.create(powerEventAdapter: powerEvents);
        addTearDown(harness.dispose);

        await harness.controller.initialize();

        expect(powerEvents.initialized, isTrue);
        expect(powerEvents.eventsAccessed, isFalse);
      },
    );

    test('disposes shared platform power and lifecycle adapter once', () async {
      final platformAdapter = _FakeSharedPlatformAdapter();
      final harness = await _Harness.create(
        powerEventAdapter: platformAdapter,
        nativeLifecycleAdapter: platformAdapter,
      );
      addTearDown(() async {
        await harness.tray.dispose();
        await harness.window.dispose();
        await harness.database.close();
      });
      await harness.controller.initialize();

      harness.controller.dispose();
      await _waitUntil(() => platformAdapter.disposeRequests == 1);

      expect(platformAdapter.powerInitialized, isTrue);
      expect(platformAdapter.lifecycleInitialized, isTrue);
      expect(platformAdapter.disposeRequests, 1);
    });

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
        expect(harness.window.closedRoles, contains(WindowRole.quickEntry));
        expect(harness.tray.latestTooltip, 'Fix bug');
      },
    );

    test(
      'lock event stops active task with system lock source and opens quick entry',
      () async {
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
        expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
        expect(harness.timers.activeTimers, isEmpty);
        expect(harness.controller.activeRole, WindowRole.quickEntry);
        expect(harness.controller.quickEntry.state.isOpen, isTrue);
        expect(harness.controller.quickEntry.state.text, isEmpty);
        expect(
          harness.controller.quickEntry.state.highlightedSuggestion?.taskText,
          'Write docs',
        );
      },
    );

    test('sleep event stops active task and leaves quick entry open', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();
      await harness.controller.openQuickEntry();
      harness.window.closedRoles.clear();

      await harness.controller.handlePowerEvent(PowerEvent.sleep);

      final events = await harness.activityLog.allEvents();
      expect(events.last.source, ActivitySource.systemSleep);
      expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.controller.quickEntry.state.text, isEmpty);
      expect(harness.window.closedRoles, isEmpty);
      expect(harness.window.focusedRoles.last, WindowRole.quickEntry);
    });

    test(
      'acknowledged sleep persists system stop at supplied timestamp',
      () async {
        final powerEvents = _FakeAcknowledgedPowerEventAdapter();
        final harness = await _Harness.create(powerEventAdapter: powerEvents);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        harness.clock.current = DateTime.utc(2026, 1, 1, 10);
        final sleepAt = DateTime.utc(2026, 1, 1, 9, 30);

        await powerEvents.emit(
          PowerEventOccurrence(event: PowerEvent.sleep, occurredAtUtc: sleepAt),
        );

        final events = await harness.activityLog.allEvents();
        expect(events.last.eventType, ActivityEventType.stopTask);
        expect(events.last.source, ActivitySource.systemSleep);
        expect(events.last.occurredAtUtc, sleepAt);
        expect(harness.controller.snapshot!.activeTask, isNull);
        expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
      },
    );

    test(
      'acknowledged shutdown prepares clean state without exiting',
      () async {
        final powerEvents = _FakeAcknowledgedPowerEventAdapter();
        final harness = await _Harness.create(
          withScheduler: true,
          powerEventAdapter: powerEvents,
        );
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();
        await harness.controller.openQuickEntry();
        harness.clock.current = DateTime.utc(2026, 1, 1, 10);
        final shutdownAt = DateTime.utc(2026, 1, 1, 9, 30);

        await powerEvents.emit(
          PowerEventOccurrence(
            event: PowerEvent.shutdown,
            occurredAtUtc: shutdownAt,
          ),
        );

        final events = await harness.activityLog.allEvents();
        expect(events.last.eventType, ActivityEventType.stopTask);
        expect(events.last.source, ActivitySource.exit);
        expect(events.last.occurredAtUtc, shutdownAt);
        expect(harness.controller.snapshot!.activeTask, isNull);
        expect(harness.controller.snapshot!.runtimeState.cleanShutdown, isTrue);
        expect(harness.exitRequests(), 0);
        expect(harness.controller.activeRole, isNull);
        expect(harness.controller.quickEntry.state.isOpen, isFalse);
        expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
        expect(harness.timers.activeTimers, isEmpty);
      },
    );

    test('cancelled shutdown reopens prompt after stopping task', () async {
      final powerEvents = _FakeAcknowledgedPowerEventAdapter();
      final harness = await _Harness.create(powerEventAdapter: powerEvents);
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await powerEvents.emit(
        PowerEventOccurrence(
          event: PowerEvent.shutdown,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 30),
        ),
      );
      harness.window.openedRoles.clear();
      harness.window.focusedRoles.clear();

      await powerEvents.emit(
        PowerEventOccurrence(
          event: PowerEvent.shutdownCancelled,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 31),
        ),
      );

      final events = await harness.activityLog.allEvents();
      expect(events.map((event) => event.eventType), [
        ActivityEventType.startTask,
        ActivityEventType.stopTask,
      ]);
      expect(events.last.source, ActivitySource.exit);
      expect(harness.exitRequests(), 0);
      expect(harness.controller.activeRole, WindowRole.quickEntry);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
      expect(harness.window.openedRoles, [WindowRole.quickEntry]);
    });

    test('shutdown while idle marks clean shutdown without exit', () async {
      final powerEvents = _FakeAcknowledgedPowerEventAdapter();
      final harness = await _Harness.create(powerEventAdapter: powerEvents);
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await powerEvents.emit(
        PowerEventOccurrence(
          event: PowerEvent.shutdown,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 30),
        ),
      );

      expect(await harness.activityLog.allEvents(), isEmpty);
      expect(harness.controller.snapshot!.runtimeState.cleanShutdown, isTrue);
      expect(harness.exitRequests(), 0);
      expect(harness.controller.activeRole, isNull);
      expect(harness.controller.quickEntry.state.isOpen, isFalse);
    });

    test('cancelled idle shutdown does not open prompt', () async {
      final powerEvents = _FakeAcknowledgedPowerEventAdapter();
      final harness = await _Harness.create(powerEventAdapter: powerEvents);
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await powerEvents.emit(
        PowerEventOccurrence(
          event: PowerEvent.shutdown,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 30),
        ),
      );
      harness.window.openedRoles.clear();
      harness.window.focusedRoles.clear();

      await powerEvents.emit(
        PowerEventOccurrence(
          event: PowerEvent.shutdownCancelled,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 31),
        ),
      );

      expect(await harness.activityLog.allEvents(), isEmpty);
      expect(harness.exitRequests(), 0);
      expect(harness.controller.activeRole, isNull);
      expect(harness.controller.quickEntry.state.isOpen, isFalse);
      expect(harness.window.openedRoles, isEmpty);
      expect(harness.window.focusedRoles, isEmpty);
    });

    test(
      'submit immediately after system stop resumes interrupted task',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();

        await harness.controller.handlePowerEvent(PowerEvent.lock);
        await harness.controller.quickEntry.submit();

        final events = await harness.activityLog.allEvents();
        expect(events.map((event) => event.eventType), [
          ActivityEventType.startTask,
          ActivityEventType.stopTask,
          ActivityEventType.startTask,
        ]);
        expect(events[1].source, ActivitySource.systemLock);
        expect(events.last.taskText, 'Write docs');
        expect(harness.controller.snapshot!.activeTask?.taskText, 'Write docs');
        expect(harness.tray.latestIconStatus, TrayIconStatus.tracking);
      },
    );

    test('external refresh applies latest icon status', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      await harness.activityLog.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: harness.clock.current,
          taskText: 'Write docs',
        ),
      );
      await harness.controller.refreshFromExternalChange();

      expect(harness.tray.latestIconStatus, TrayIconStatus.tracking);
      expect(harness.tray.latestTooltip, 'Write docs');

      harness.clock.current = harness.clock.current.add(
        const Duration(minutes: 5),
      );
      await harness.activityLog.append(
        ActivityLogEvent.stopTask(
          occurredAtUtc: harness.clock.current,
          source: ActivitySource.manualStop,
        ),
      );
      await harness.controller.refreshFromExternalChange();

      expect(harness.tray.latestIconStatus, TrayIconStatus.idle);
      expect(harness.tray.latestTooltip, 'No current task');
    });

    test(
      'power event while idle does not append a stop event or prompt',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        harness.window.emitCloseRequest(WindowRole.quickEntry);
        await Future<void>.delayed(Duration.zero);
        harness.window.openedRoles.clear();
        harness.window.focusedRoles.clear();

        await harness.controller.handlePowerEvent(PowerEvent.lock);

        expect(await harness.activityLog.allEvents(), isEmpty);
        expect(harness.controller.activeRole, isNull);
        expect(harness.controller.quickEntry.state.isOpen, isFalse);
        expect(harness.window.openedRoles, isEmpty);
        expect(harness.window.focusedRoles, isEmpty);
        expect(
          harness.tray.latestEntries
              .singleWhere((entry) => entry.action == TrayMenuAction.stopTask)
              .enabled,
          isFalse,
        );
      },
    );

    test('duplicate power events do not append duplicate stops', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.controller.initialize();
      await harness.controller.openQuickEntry();
      await harness.controller.quickEntry.updateText('Write docs');
      await harness.controller.quickEntry.submit();

      await harness.controller.handlePowerEvent(PowerEvent.lock);
      await harness.controller.handlePowerEvent(PowerEvent.sleep);

      final events = await harness.activityLog.allEvents();
      expect(events.map((event) => event.eventType), [
        ActivityEventType.startTask,
        ActivityEventType.stopTask,
      ]);
      expect(events.last.source, ActivitySource.systemLock);
      expect(harness.controller.quickEntry.state.isOpen, isTrue);
    });

    test(
      'duplicate acknowledged events do not append duplicate stops',
      () async {
        final powerEvents = _FakeAcknowledgedPowerEventAdapter();
        final harness = await _Harness.create(powerEventAdapter: powerEvents);
        addTearDown(harness.dispose);
        await harness.controller.initialize();
        await harness.controller.openQuickEntry();
        await harness.controller.quickEntry.updateText('Write docs');
        await harness.controller.quickEntry.submit();

        await powerEvents.emit(
          PowerEventOccurrence(
            event: PowerEvent.lock,
            occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 30),
          ),
        );
        await powerEvents.emit(
          PowerEventOccurrence(
            event: PowerEvent.sleep,
            occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 31),
          ),
        );

        final events = await harness.activityLog.allEvents();
        expect(events.map((event) => event.eventType), [
          ActivityEventType.startTask,
          ActivityEventType.stopTask,
        ]);
        expect(events.last.source, ActivitySource.systemLock);
      },
    );

    test('power event stream errors surface as runtime errors', () async {
      final powerEvents = _FakePowerEventAdapter();
      addTearDown(powerEvents.dispose);
      final harness = await _Harness.create(powerEventAdapter: powerEvents);
      addTearDown(harness.dispose);
      await harness.controller.initialize();

      powerEvents.emitError(StateError('power stream failed'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        harness.controller.runtimeErrorMessage,
        contains('power stream failed'),
      );
      expect(harness.window.resizedConfigurations.last.title, 'wyd error');
      expect(harness.window.focusedRoles.last, WindowRole.quickEntry);
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for async controller action.');
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
    required this.nativeLifecycle,
    required this.controller,
    required this.exitRequests,
    required this.hideResidentWindowRequests,
  });

  final AppDatabase database;
  final SqliteActivityLogRepository activityLog;
  final _FakeTrayAdapter tray;
  final _FakeWindowAdapter window;
  final _FakeClock clock;
  final _FakeSchedulerTimerFactory timers;
  final _FakeSingleInstanceAdapter singleInstance;
  final _FakeNativeLifecycleAdapter nativeLifecycle;
  final WydAppController controller;
  final int Function() exitRequests;
  final int Function() hideResidentWindowRequests;

  static Future<_Harness> create({
    bool withScheduler = false,
    bool withSingleInstance = false,
    bool withNativeLifecycle = false,
    bool trayFailsOnInitialize = false,
    Duration? secondaryWindowWarmUpDelay,
    PowerEventAdapter powerEventAdapter = const UnsupportedPowerEventAdapter(),
    NativeLifecycleAdapter? nativeLifecycleAdapter,
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
    final nativeLifecycle = _FakeNativeLifecycleAdapter();
    var exitRequests = 0;
    var hideResidentWindowRequests = 0;
    late final WydAppController controller;
    final scheduler = withScheduler
        ? NagScheduler(
            clock: clock,
            timerFactory: timers,
            userIdleDetector: const UnsupportedUserIdleDetector(),
            onShowPrompt: () => controller.showNagPrompt(),
            onPromptTimedOut: () => controller.nagPromptTimedOut(),
            onError: (error, stackTrace) =>
                unawaited(controller.handleRuntimeError(error, stackTrace)),
          )
        : null;
    controller = WydAppController(
      trackerService: service,
      trayAdapter: tray,
      windowCoordinator: WindowCoordinator(window),
      nagScheduler: scheduler,
      singleInstanceAdapter: withSingleInstance ? singleInstance : null,
      nativeLifecycleAdapter:
          nativeLifecycleAdapter ??
          (withNativeLifecycle ? nativeLifecycle : null),
      powerEventAdapter: powerEventAdapter,
      secondaryWindowWarmUpDelay: secondaryWindowWarmUpDelay,
      hideResidentWindow: () async {
        hideResidentWindowRequests += 1;
      },
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
      nativeLifecycle: nativeLifecycle,
      controller: controller,
      exitRequests: () => exitRequests,
      hideResidentWindowRequests: () => hideResidentWindowRequests,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await tray.dispose();
    await window.dispose();
    await database.close();
  }
}

final class _FakePowerEventAdapter implements PowerEventAdapter {
  final StreamController<PowerEvent> _events =
      StreamController<PowerEvent>.broadcast();

  @override
  Stream<PowerEvent> get events => _events.stream;

  void emitError(Object error) {
    _events.addError(error, StackTrace.current);
  }

  Future<void> dispose() async {
    await _events.close();
  }
}

final class _FakeAcknowledgedPowerEventAdapter
    implements AcknowledgedPowerEventAdapter {
  bool initialized = false;
  bool eventsAccessed = false;
  Future<void> Function(PowerEventOccurrence occurrence)? _onPowerEvent;

  @override
  Stream<PowerEvent> get events {
    eventsAccessed = true;
    return const Stream.empty();
  }

  @override
  Future<void> initializeAcknowledged(
    Future<void> Function(PowerEventOccurrence occurrence) onPowerEvent,
  ) async {
    initialized = true;
    _onPowerEvent = onPowerEvent;
  }

  Future<void> emit(PowerEventOccurrence occurrence) async {
    final onPowerEvent = _onPowerEvent;
    if (onPowerEvent == null) {
      throw StateError('Acknowledged power adapter is not initialized.');
    }
    await onPowerEvent(occurrence);
  }
}

final class _FakeSharedPlatformAdapter
    implements
        AcknowledgedPowerEventAdapter,
        NativeLifecycleAdapter,
        DisposablePlatformAdapter {
  bool powerInitialized = false;
  bool lifecycleInitialized = false;
  bool _disposed = false;
  var disposeRequests = 0;

  @override
  Stream<PowerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize(
    Future<void> Function() onTerminationRequested,
  ) async {
    lifecycleInitialized = true;
  }

  @override
  Future<void> initializeAcknowledged(
    Future<void> Function(PowerEventOccurrence occurrence) onPowerEvent,
  ) async {
    powerInitialized = true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    disposeRequests += 1;
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

final class _FakeNativeLifecycleAdapter implements NativeLifecycleAdapter {
  Future<void> Function()? _onTerminationRequested;

  @override
  Future<void> initialize(
    Future<void> Function() onTerminationRequested,
  ) async {
    _onTerminationRequested = onTerminationRequested;
  }

  Future<void> requestTermination() async {
    await _onTerminationRequested?.call();
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
  TrayIconStatus? initializedIconStatus;
  TrayIconStatus? latestIconStatus;
  String? initializedTooltip;
  String? latestTooltip;
  final List<TrayIconStatus> iconStatuses = [];
  final List<String> tooltips = [];

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(
    List<TrayMenuEntry> entries, {
    required TrayIconStatus iconStatus,
    required String tooltip,
  }) async {
    if (failsOnInitialize) {
      throw StateError('tray unavailable');
    }
    initialized = true;
    latestEntries = entries;
    initializedIconStatus = iconStatus;
    latestIconStatus = iconStatus;
    initializedTooltip = tooltip;
    latestTooltip = tooltip;
    iconStatuses.add(iconStatus);
    tooltips.add(tooltip);
  }

  @override
  Future<void> updateMenu(List<TrayMenuEntry> entries) async {
    latestEntries = entries;
  }

  @override
  Future<void> updateIcon(TrayIconStatus iconStatus) async {
    latestIconStatus = iconStatus;
    iconStatuses.add(iconStatus);
  }

  @override
  Future<void> updateTooltip(String tooltip) async {
    latestTooltip = tooltip;
    tooltips.add(tooltip);
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
  final Set<WindowRole> failingOpenRoles = {};
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
    if (failingOpenRoles.contains(configuration.role)) {
      throw StateError('window open failed');
    }
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
