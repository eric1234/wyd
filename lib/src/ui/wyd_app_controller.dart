import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/application.dart';
import '../domain/domain.dart';
import 'quick_entry/quick_entry.dart';
import 'report/report.dart';
import 'settings/settings.dart';

final class WydAppController extends ChangeNotifier {
  WydAppController({
    required TrackerService trackerService,
    required TrayAdapter trayAdapter,
    required WindowCoordinator windowCoordinator,
    required Future<void> Function() onExit,
    NagScheduler? nagScheduler,
    SingleInstanceAdapter? singleInstanceAdapter,
    PowerEventAdapter powerEventAdapter = const UnsupportedPowerEventAdapter(),
    Duration? secondaryWindowWarmUpDelay = const Duration(seconds: 1),
    this.reportController,
    this.settingsController,
  }) : _trackerService = trackerService,
       _trayAdapter = trayAdapter,
       _windowCoordinator = windowCoordinator,
       _onExit = onExit,
       _nagScheduler = nagScheduler,
       _singleInstanceAdapter = singleInstanceAdapter,
       _powerEventAdapter = powerEventAdapter,
       _secondaryWindowWarmUpDelay = secondaryWindowWarmUpDelay {
    quickEntry = QuickEntryController(
      client: TrackerQuickEntryClient(_trackerService),
      onSubmitted: _quickEntrySubmitted,
    );
    _windowCloseSubscription = _windowCoordinator.closeRequests.listen(
      (role) => unawaited(handleWindowClosed(role)),
    );
  }

  final TrackerService _trackerService;
  final TrayAdapter _trayAdapter;
  final WindowCoordinator _windowCoordinator;
  final Future<void> Function() _onExit;
  final NagScheduler? _nagScheduler;
  final SingleInstanceAdapter? _singleInstanceAdapter;
  final PowerEventAdapter _powerEventAdapter;
  final Duration? _secondaryWindowWarmUpDelay;

  final ReportController? reportController;
  final SettingsController? settingsController;

  late final QuickEntryController quickEntry;
  StreamSubscription<TrayMenuAction>? _menuSubscription;
  StreamSubscription<void>? _primaryClickSubscription;
  StreamSubscription<WindowRole>? _windowCloseSubscription;
  StreamSubscription<PowerEvent>? _powerEventSubscription;
  Timer? _secondaryWindowWarmUpTimer;

  AppStateSnapshot? _snapshot;
  WindowRole? _activeRole;
  String? _startupError;
  bool _initialized = false;

  AppStateSnapshot? get snapshot => _snapshot;
  WindowRole? get activeRole => _activeRole;
  String? get startupError => _startupError;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      _snapshot = await _trackerService.recoverOnStartup();
      await _trayAdapter.initialize(TrayMenuPresenter.build(_snapshot!));
      await _singleInstanceAdapter?.initialize(openQuickEntry);
      _menuSubscription = _trayAdapter.menuActions.listen(_handleTrayAction);
      _primaryClickSubscription = _trayAdapter.primaryClicks.listen(
        (_) => unawaited(openQuickEntry()),
      );
      _powerEventSubscription = _powerEventAdapter.events.listen(
        (event) => unawaited(handlePowerEvent(event)),
      );
      _nagScheduler?.update(_snapshot!);
      notifyListeners();
      _scheduleSecondaryWindowWarmUp();
    } catch (error) {
      _startupError = error.toString();
      _activeRole = WindowRole.settings;
      notifyListeners();
      await _windowCoordinator.openOrFocus(WindowRole.settings);
    }
  }

  Future<void> openQuickEntry() async {
    await _openQuickEntry();
  }

  Future<AppStateSnapshot> showNagPrompt() async {
    await _openQuickEntry();
    return _snapshot!;
  }

  Future<void> _openQuickEntry() async {
    var latestSnapshot = await _trackerService.loadSnapshot();
    if (latestSnapshot.activeTask != null &&
        latestSnapshot.runtimeState.promptState.status == PromptStatus.none) {
      latestSnapshot = await _trackerService.nagPromptShown();
    }
    _snapshot = latestSnapshot;
    await quickEntry.open(latestSnapshot);

    _activeRole = WindowRole.quickEntry;
    notifyListeners();
    await _windowCoordinator.openOrFocus(
      WindowRole.quickEntry,
      configuration: WindowRoleConfiguration.quickEntry(),
    );

    await _refreshTrayMenu(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
  }

  Future<void> openReport() async {
    await _windowCoordinator.openOrFocus(WindowRole.report);
  }

  Future<void> openSettings() async {
    await _windowCoordinator.openOrFocus(WindowRole.settings);
  }

  Future<void> stopTask() async {
    final latestSnapshot = await _trackerService.stopTask(
      source: ActivitySource.manualStop,
    );
    _snapshot = latestSnapshot;
    final shouldCloseQuickEntryWindow = _activeRole == WindowRole.quickEntry;
    quickEntry.close();
    if (shouldCloseQuickEntryWindow) {
      await _windowCoordinator.close(WindowRole.quickEntry);
    }
    await _refreshTrayMenu(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    notifyListeners();
  }

  Future<void> handlePowerEvent(PowerEvent event) async {
    final beforeSnapshot = await _trackerService.loadSnapshot();
    if (beforeSnapshot.activeTask == null) {
      _snapshot = beforeSnapshot;
      await _refreshTrayMenu(beforeSnapshot);
      _nagScheduler?.update(beforeSnapshot);
      notifyListeners();
      return;
    }

    final latestSnapshot = await _trackerService.stopTask(
      source: switch (event) {
        PowerEvent.lock => ActivitySource.systemLock,
        PowerEvent.sleep => ActivitySource.systemSleep,
      },
    );
    _snapshot = latestSnapshot;
    final shouldCloseQuickEntryWindow = _activeRole == WindowRole.quickEntry;
    quickEntry.close();
    if (shouldCloseQuickEntryWindow) {
      await _windowCoordinator.close(WindowRole.quickEntry);
    }
    await _refreshTrayMenu(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    notifyListeners();
  }

  Future<AppStateSnapshot> nagPromptTimedOut() async {
    final latestSnapshot = await _trackerService.nagPromptTimedOut();
    _snapshot = latestSnapshot;
    await _refreshTrayMenu(latestSnapshot);
    notifyListeners();
    return latestSnapshot;
  }

  Future<void> handleWindowClosed(WindowRole role) async {
    switch (role) {
      case WindowRole.quickEntry:
        if (_activeRole == WindowRole.quickEntry) {
          _activeRole = null;
        }
        quickEntry.close();
      case WindowRole.report:
        reportController?.close();
        if (_activeRole == WindowRole.report) {
          _activeRole = null;
        }
      case WindowRole.settings:
        await settingsController?.close();
        if (_activeRole == WindowRole.settings) {
          _activeRole = null;
        }
    }
    notifyListeners();
  }

  Future<void> exitRequested() async {
    final latestSnapshot = await _trackerService.exitRequested();
    _snapshot = latestSnapshot;
    await _refreshTrayMenu(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    quickEntry.close();
    _activeRole = null;
    await _bestEffortExitCleanup();
    await _onExit();
  }

  @override
  void dispose() {
    _menuSubscription?.cancel();
    _primaryClickSubscription?.cancel();
    _windowCloseSubscription?.cancel();
    _powerEventSubscription?.cancel();
    _secondaryWindowWarmUpTimer?.cancel();
    quickEntry.dispose();
    reportController?.dispose();
    settingsController?.dispose();
    _nagScheduler?.dispose();
    super.dispose();
  }

  Future<void> _quickEntrySubmitted(AppStateSnapshot snapshot) async {
    _snapshot = snapshot;
    _activeRole = null;
    await _windowCoordinator.close(WindowRole.quickEntry);
    await _refreshTrayMenu(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  Future<void> settingsSaved(AppStateSnapshot snapshot) async {
    _snapshot = snapshot;
    await _refreshTrayMenu(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  Future<void> refreshFromExternalChange() async {
    final snapshot = await _trackerService.loadSnapshot();
    _snapshot = snapshot;
    await _refreshTrayMenu(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  void _handleTrayAction(TrayMenuAction action) {
    unawaited(() async {
      switch (action) {
        case TrayMenuAction.updateTask:
          await openQuickEntry();
        case TrayMenuAction.stopTask:
          await stopTask();
        case TrayMenuAction.report:
          await openReport();
        case TrayMenuAction.settings:
          await openSettings();
        case TrayMenuAction.exit:
          await exitRequested();
      }
    }());
  }

  Future<void> _refreshTrayMenu(AppStateSnapshot snapshot) {
    return _trayAdapter.updateMenu(TrayMenuPresenter.build(snapshot));
  }

  void _scheduleSecondaryWindowWarmUp() {
    final delay = _secondaryWindowWarmUpDelay;
    if (delay == null) {
      return;
    }

    _secondaryWindowWarmUpTimer?.cancel();
    _secondaryWindowWarmUpTimer = Timer(delay, () {
      _secondaryWindowWarmUpTimer = null;
      unawaited(_warmUpSecondaryWindows());
    });
  }

  Future<void> _warmUpSecondaryWindows() async {
    for (final role in [WindowRole.report, WindowRole.settings]) {
      try {
        await _windowCoordinator.preload(role);
      } catch (_) {
        // Window warm-up is only an optimization; normal open remains available.
      }
    }
  }

  Future<void> _bestEffortExitCleanup() async {
    try {
      await _trayAdapter.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The process is exiting; stale tray cleanup is preferable to hanging.
    }
  }
}
