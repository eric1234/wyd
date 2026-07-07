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
    NativeLifecycleAdapter? nativeLifecycleAdapter,
    PowerEventAdapter powerEventAdapter = const UnsupportedPowerEventAdapter(),
    Duration? secondaryWindowWarmUpDelay = const Duration(seconds: 1),
    Future<void> Function(AppStateSnapshot snapshot)? startupAtLoginReconciler,
    Future<void> Function()? hideResidentWindow,
    this.reportController,
    this.settingsController,
  }) : _trackerService = trackerService,
       _trayAdapter = trayAdapter,
       _windowCoordinator = windowCoordinator,
       _onExit = onExit,
       _nagScheduler = nagScheduler,
       _singleInstanceAdapter = singleInstanceAdapter,
       _nativeLifecycleAdapter = nativeLifecycleAdapter,
       _powerEventAdapter = powerEventAdapter,
       _secondaryWindowWarmUpDelay = secondaryWindowWarmUpDelay,
       _startupAtLoginReconciler = startupAtLoginReconciler,
       _hideResidentWindow = hideResidentWindow {
    quickEntry = QuickEntryController(
      client: TrackerQuickEntryClient(_trackerService),
      onSubmitted: _quickEntrySubmitted,
    );
    _windowCloseSubscription = _windowCoordinator.closeRequests.listen(
      (role) => unawaited(_runUserAction(() => handleWindowClosed(role))),
    );
  }

  final TrackerService _trackerService;
  final TrayAdapter _trayAdapter;
  final WindowCoordinator _windowCoordinator;
  final Future<void> Function() _onExit;
  final NagScheduler? _nagScheduler;
  final SingleInstanceAdapter? _singleInstanceAdapter;
  final NativeLifecycleAdapter? _nativeLifecycleAdapter;
  final PowerEventAdapter _powerEventAdapter;
  final Duration? _secondaryWindowWarmUpDelay;
  final Future<void> Function(AppStateSnapshot snapshot)?
  _startupAtLoginReconciler;
  final Future<void> Function()? _hideResidentWindow;

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
  String? _runtimeErrorMessage;
  bool _initialized = false;
  bool _platformAdaptersDisposed = false;

  AppStateSnapshot? get snapshot => _snapshot;
  WindowRole? get activeRole => _activeRole;
  String? get startupError => _startupError;
  String? get runtimeErrorMessage => _runtimeErrorMessage;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      await _hideResidentWindow?.call();
      _snapshot = await _trackerService.recoverOnStartup();
      final snapshot = _snapshot!;
      await _trayAdapter.initialize(
        TrayMenuPresenter.build(snapshot),
        iconStatus: TrayMenuPresenter.buildIconStatus(snapshot),
        tooltip: TrayMenuPresenter.buildTooltip(snapshot),
      );
      await _singleInstanceAdapter?.initialize(openQuickEntry);
      await _nativeLifecycleAdapter?.initialize(exitRequested);
      _menuSubscription = _trayAdapter.menuActions.listen(_handleTrayAction);
      _primaryClickSubscription = _trayAdapter.primaryClicks.listen(
        (_) => unawaited(_runUserAction(openQuickEntry)),
      );
      if (_powerEventAdapter case final AcknowledgedPowerEventAdapter adapter) {
        await adapter.initializeAcknowledged(_handleAcknowledgedPowerEvent);
      } else {
        _powerEventSubscription = _powerEventAdapter.events.listen(
          (event) => unawaited(_runUserAction(() => handlePowerEvent(event))),
          onError: (Object error, StackTrace stackTrace) {
            unawaited(handleRuntimeError(error, stackTrace));
          },
        );
      }
      await _openQuickEntry();
      await _reconcileStartupAtLogin(_snapshot!);
      _scheduleSecondaryWindowWarmUp();
    } catch (error) {
      await _showFatalStartupError(error);
    }
  }

  Future<void> openQuickEntry() async {
    await _openQuickEntry();
  }

  Future<AppStateSnapshot> showNagPrompt() async {
    await _openQuickEntry();
    return _snapshot!;
  }

  Future<void> _openQuickEntry({AppStateSnapshot? snapshot}) async {
    var latestSnapshot = snapshot ?? await _trackerService.loadSnapshot();
    final shouldMarkPromptVisible =
        latestSnapshot.activeTask != null &&
        latestSnapshot.runtimeState.promptState.status == PromptStatus.none;
    _snapshot = latestSnapshot;
    await quickEntry.open(latestSnapshot);

    _activeRole = WindowRole.quickEntry;
    notifyListeners();

    var windowOpened = false;
    try {
      await _windowCoordinator.openOrFocus(
        WindowRole.quickEntry,
        configuration: WindowRoleConfiguration.quickEntry(),
      );
      windowOpened = true;

      if (shouldMarkPromptVisible) {
        try {
          latestSnapshot = await _trackerService.nagPromptShown();
          _snapshot = latestSnapshot;
        } catch (_) {
          quickEntry.close();
          _activeRole = null;
          notifyListeners();
          await _closeQuickEntryBestEffort();
          rethrow;
        }
      }
    } catch (_) {
      if (!windowOpened) {
        quickEntry.close();
        _activeRole = null;
        notifyListeners();
      }
      rethrow;
    }

    await _refreshTray(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    notifyListeners();
  }

  Future<void> openReport() async {
    await _windowCoordinator.openOrFocus(WindowRole.report);
  }

  Future<void> openSettings() async {
    await _windowCoordinator.openOrFocus(WindowRole.settings);
  }

  Future<void> stopTask() async {
    await _stopTaskAndOpenPrompt(ActivitySource.manualStop);
  }

  Future<void> handlePowerEvent(PowerEvent event) async {
    await _handlePowerEvent(event: event, openPromptSynchronously: true);
  }

  Future<void> _handleAcknowledgedPowerEvent(
    PowerEventOccurrence occurrence,
  ) async {
    await _runUserAction(
      () => _handlePowerEvent(
        event: occurrence.event,
        occurredAtUtc: occurrence.occurredAtUtc,
        openPromptSynchronously: false,
      ),
    );
  }

  Future<void> _handlePowerEvent({
    required PowerEvent event,
    DateTime? occurredAtUtc,
    required bool openPromptSynchronously,
  }) async {
    if (event == PowerEvent.shutdown) {
      await _prepareForSystemShutdown(occurredAtUtc: occurredAtUtc);
      return;
    }

    final beforeSnapshot = await _trackerService.loadSnapshot();
    if (beforeSnapshot.activeTask == null) {
      _snapshot = beforeSnapshot;
      await _refreshTray(beforeSnapshot);
      _nagScheduler?.update(beforeSnapshot);
      notifyListeners();
      return;
    }

    final source = switch (event) {
      PowerEvent.lock => ActivitySource.systemLock,
      PowerEvent.sleep => ActivitySource.systemSleep,
      PowerEvent.shutdown => throw StateError('Shutdown handled separately.'),
    };
    if (openPromptSynchronously) {
      await _stopTaskAndOpenPrompt(source, occurredAtUtc: occurredAtUtc);
      return;
    }

    final latestSnapshot = await _trackerService.stopTask(
      source: source,
      occurredAtUtc: occurredAtUtc,
    );
    _snapshot = latestSnapshot;
    quickEntry.close();
    await _refreshTray(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    notifyListeners();
    unawaited(_runUserAction(() => _openQuickEntry(snapshot: latestSnapshot)));
  }

  Future<AppStateSnapshot> nagPromptTimedOut() async {
    final latestSnapshot = await _trackerService.nagPromptTimedOut();
    _snapshot = latestSnapshot;
    await _refreshTray(latestSnapshot);
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
    await _refreshTray(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    quickEntry.close();
    _activeRole = null;
    await _bestEffortExitCleanup();
    await _onExit();
  }

  Future<void> _prepareForSystemShutdown({DateTime? occurredAtUtc}) async {
    final latestSnapshot = await _trackerService.exitRequested(
      occurredAtUtc: occurredAtUtc,
    );
    _snapshot = latestSnapshot;
    await _refreshTray(latestSnapshot);
    _nagScheduler?.update(latestSnapshot);
    quickEntry.close();
    _activeRole = null;
    notifyListeners();
  }

  Future<void> exitAfterStartupError() async {
    try {
      await _trackerService.exitRequested();
    } catch (_) {
      // Startup may have failed because persistence is unavailable. Exiting is
      // still the safest outcome after the error has been shown.
    }
    await _bestEffortExitCleanup();
    await _onExit();
  }

  Future<void> dismissRuntimeError() async {
    _runtimeErrorMessage = null;
    if (_activeRole == WindowRole.quickEntry && !quickEntry.state.isOpen) {
      _activeRole = null;
      notifyListeners();
      await _closeQuickEntryBestEffort();
      return;
    }
    notifyListeners();
  }

  Future<void> handleRuntimeError(Object error, [StackTrace? _]) async {
    _runtimeErrorMessage = error.toString();
    quickEntry.close();
    _activeRole = WindowRole.quickEntry;
    notifyListeners();
    try {
      await _windowCoordinator.openOrFocus(
        WindowRole.quickEntry,
        configuration: WindowRoleConfiguration.runtimeError(),
      );
    } catch (_) {
      // If the error window cannot be shown, keep the error in controller state
      // so it is still visible if another window is later opened successfully.
    }
  }

  @override
  void dispose() {
    _menuSubscription?.cancel();
    _primaryClickSubscription?.cancel();
    _windowCloseSubscription?.cancel();
    _powerEventSubscription?.cancel();
    _secondaryWindowWarmUpTimer?.cancel();
    _disposePlatformAdapters();
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
    await _refreshTray(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  Future<void> settingsSaved(AppStateSnapshot snapshot) async {
    _snapshot = snapshot;
    await _refreshTray(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  Future<void> refreshFromExternalChange() async {
    final snapshot = await _trackerService.loadSnapshot();
    _snapshot = snapshot;
    await _refreshTray(snapshot);
    _nagScheduler?.update(snapshot);
    notifyListeners();
  }

  void _handleTrayAction(TrayMenuAction action) {
    unawaited(
      _runUserAction(() async {
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
      }),
    );
  }

  Future<void> _refreshTray(AppStateSnapshot snapshot) async {
    await _trayAdapter.updateIcon(TrayMenuPresenter.buildIconStatus(snapshot));
    await _trayAdapter.updateTooltip(TrayMenuPresenter.buildTooltip(snapshot));
    await _trayAdapter.updateMenu(TrayMenuPresenter.build(snapshot));
  }

  Future<void> _stopTaskAndOpenPrompt(
    ActivitySource source, {
    DateTime? occurredAtUtc,
  }) async {
    final latestSnapshot = await _trackerService.stopTask(
      source: source,
      occurredAtUtc: occurredAtUtc,
    );
    _snapshot = latestSnapshot;
    quickEntry.close();
    await _openQuickEntry(snapshot: latestSnapshot);
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

  Future<void> _showFatalStartupError(Object error) async {
    await _disposePlatformAdaptersBestEffort();
    _startupError = error.toString();
    _activeRole = WindowRole.quickEntry;
    notifyListeners();
    try {
      await _windowCoordinator.openOrFocus(
        WindowRole.quickEntry,
        configuration: WindowRoleConfiguration.startupError(),
      );
    } catch (_) {
      await _bestEffortExitCleanup();
      await _onExit();
    }
  }

  Future<void> _reconcileStartupAtLogin(AppStateSnapshot snapshot) async {
    final reconciler = _startupAtLoginReconciler;
    if (reconciler == null) {
      return;
    }

    try {
      await reconciler(snapshot);
    } catch (error, stackTrace) {
      await handleRuntimeError(error, stackTrace);
    }
  }

  Future<void> _runUserAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      await handleRuntimeError(error, stackTrace);
    }
  }

  Future<void> _closeQuickEntryBestEffort() async {
    try {
      await _windowCoordinator.close(WindowRole.quickEntry);
    } catch (_) {
      // Runtime error surfacing should not be blocked by cleanup failure.
    }
  }

  Future<void> _bestEffortExitCleanup() async {
    try {
      await _trayAdapter.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The process is exiting; stale tray cleanup is preferable to hanging.
    }
  }

  void _disposePlatformAdapters() {
    unawaited(_disposePlatformAdaptersBestEffort());
  }

  Future<void> _disposePlatformAdaptersBestEffort() async {
    if (_platformAdaptersDisposed) {
      return;
    }
    _platformAdaptersDisposed = true;

    final adapters = <DisposablePlatformAdapter>{};
    if (_powerEventAdapter case final DisposablePlatformAdapter adapter) {
      adapters.add(adapter);
    }
    if (_nativeLifecycleAdapter case final DisposablePlatformAdapter adapter) {
      adapters.add(adapter);
    }

    await Future.wait(adapters.map(_disposePlatformAdapter));
  }

  Future<void> _disposePlatformAdapter(
    DisposablePlatformAdapter adapter,
  ) async {
    try {
      await adapter.dispose();
    } catch (_) {
      // Controller disposal should not surface late platform cleanup failures.
    }
  }
}
