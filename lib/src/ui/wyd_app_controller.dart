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
  bool _disposed = false;
  bool _platformAdaptersDisposed = false;
  bool _shutdownPreparationStoppedActiveTask = false;
  bool _systemStopPromptPending = false;
  bool _terminationPreparationStarted = false;
  bool _manualExitInProgress = false;
  int _deferredSystemUiGeneration = 0;
  Future<void> _systemEventChain = Future.value();

  AppStateSnapshot? get snapshot => _snapshot;
  WindowRole? get activeRole => _activeRole;
  String? get startupError => _startupError;
  String? get runtimeErrorMessage => _runtimeErrorMessage;
  bool get initialized => _initialized;
  bool get _terminationInProgress {
    return _terminationPreparationStarted || _manualExitInProgress;
  }

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
      await _nativeLifecycleAdapter?.initialize(_prepareForNativeTermination);
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
      if (_terminationInProgress) {
        return;
      }
      await _openQuickEntry();
      if (_terminationInProgress) {
        return;
      }
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

  Future<void> _openQuickEntry({
    AppStateSnapshot? snapshot,
    int? expectedSystemUiGeneration,
    bool refreshIdleSuggestions = true,
  }) async {
    if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
      return;
    }
    var latestSnapshot = snapshot ?? await _trackerService.loadSnapshot();
    if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
      return;
    }
    final shouldMarkPromptVisible =
        latestSnapshot.activeTask != null &&
        latestSnapshot.runtimeState.promptState.status == PromptStatus.none;
    _snapshot = latestSnapshot;
    await quickEntry.open(
      latestSnapshot,
      refreshIdleSuggestions: refreshIdleSuggestions,
    );
    if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
      quickEntry.close();
      return;
    }

    _activeRole = WindowRole.quickEntry;
    notifyListeners();

    var windowOpened = false;
    try {
      await _windowCoordinator.openOrFocus(
        WindowRole.quickEntry,
        configuration: WindowRoleConfiguration.quickEntry(),
      );
      windowOpened = true;
      if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
        quickEntry.close();
        _activeRole = null;
        notifyListeners();
        await _closeQuickEntryBestEffort();
        return;
      }

      if (shouldMarkPromptVisible) {
        try {
          latestSnapshot = await _trackerService.nagPromptShown();
          _snapshot = latestSnapshot;
          if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
            quickEntry.close();
            _activeRole = null;
            notifyListeners();
            await _closeQuickEntryBestEffort();
            return;
          }
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
    if (_shouldAbortQuickEntryOpen(expectedSystemUiGeneration)) {
      quickEntry.close();
      _activeRole = null;
      notifyListeners();
      await _closeQuickEntryBestEffort();
      return;
    }
    _nagScheduler?.update(latestSnapshot);
    notifyListeners();
  }

  bool _shouldAbortQuickEntryOpen(int? expectedSystemUiGeneration) {
    return _terminationInProgress ||
        expectedSystemUiGeneration != null &&
            expectedSystemUiGeneration != _deferredSystemUiGeneration;
  }

  Future<void> openReport() async {
    await _openRoleUnlessTerminating(WindowRole.report);
  }

  Future<void> openSettings() async {
    await _openRoleUnlessTerminating(WindowRole.settings);
  }

  Future<void> openAbout() async {
    await _openRoleUnlessTerminating(WindowRole.about);
  }

  Future<void> _openRoleUnlessTerminating(WindowRole role) async {
    if (_terminationInProgress) {
      return;
    }
    await _windowCoordinator.openOrFocus(role);
    if (_terminationInProgress) {
      await _windowCoordinator.close(role);
    }
  }

  Future<void> stopTask() async {
    await _stopTaskAndOpenPrompt(ActivitySource.manualStop);
  }

  Future<void> handlePowerEvent(PowerEvent event) async {
    await _handlePowerEvent(event: event, openPromptSynchronously: true);
  }

  Future<void> _handleAcknowledgedPowerEvent(PowerEventOccurrence occurrence) {
    return _enqueueSystemEvent(
      () => _persistAcknowledgedPowerEvent(occurrence),
    );
  }

  Future<void> _persistAcknowledgedPowerEvent(
    PowerEventOccurrence occurrence,
  ) async {
    switch (occurrence.event) {
      case PowerEvent.lock:
        await _persistAcknowledgedSystemStop(
          source: ActivitySource.systemLock,
          occurredAtUtc: occurrence.occurredAtUtc,
        );
      case PowerEvent.sleep:
        await _persistAcknowledgedSystemStop(
          source: ActivitySource.systemSleep,
          occurredAtUtc: occurrence.occurredAtUtc,
        );
      case PowerEvent.shutdown:
        final result = await _trackerService.prepareForSystemShutdown(
          occurredAtUtc: occurrence.occurredAtUtc,
        );
        _applySystemBoundaryResult(result);
        _systemStopPromptPending =
            _systemStopPromptPending || result.didStopActiveTask;
        _schedulePreparedShutdownUi();
      case PowerEvent.shutdownCancelled:
        final shouldOpenPrompt = _systemStopPromptPending;
        _scheduleShutdownCancellationUi(shouldOpenPrompt: shouldOpenPrompt);
    }
  }

  Future<void> _persistAcknowledgedSystemStop({
    required ActivitySource source,
    required DateTime occurredAtUtc,
  }) async {
    final result = await _trackerService.stopForSystemBoundary(
      source: source,
      occurredAtUtc: occurredAtUtc,
    );
    _applySystemBoundaryResult(result);
    _systemStopPromptPending =
        _systemStopPromptPending || result.didStopActiveTask;
    _scheduleSystemStopUi();
  }

  void _applySystemBoundaryResult(SystemBoundaryResult result) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    _snapshot = snapshot.copyWith(
      activeTask: result.activeTask,
      clearActiveTask: result.activeTask == null,
      runtimeState: result.runtimeState,
      busy: false,
      clearErrorMessage: true,
    );
  }

  Future<void> _handlePowerEvent({
    required PowerEvent event,
    DateTime? occurredAtUtc,
    required bool openPromptSynchronously,
  }) async {
    switch (event) {
      case PowerEvent.shutdown:
        await _prepareForSystemShutdown(occurredAtUtc: occurredAtUtc);
      case PowerEvent.shutdownCancelled:
        await _handleShutdownCancelled();
      case PowerEvent.lock:
        await _handleSystemStop(
          source: ActivitySource.systemLock,
          occurredAtUtc: occurredAtUtc,
          openPromptSynchronously: openPromptSynchronously,
        );
      case PowerEvent.sleep:
        await _handleSystemStop(
          source: ActivitySource.systemSleep,
          occurredAtUtc: occurredAtUtc,
          openPromptSynchronously: openPromptSynchronously,
        );
    }
  }

  Future<void> _handleSystemStop({
    required ActivitySource source,
    required bool openPromptSynchronously,
    DateTime? occurredAtUtc,
  }) async {
    final beforeSnapshot = await _trackerService.loadSnapshot();
    if (beforeSnapshot.activeTask == null) {
      await _applySnapshot(beforeSnapshot, notify: true);
      return;
    }
    if (openPromptSynchronously) {
      await _stopTaskAndOpenPrompt(source, occurredAtUtc: occurredAtUtc);
      return;
    }

    final latestSnapshot = await _trackerService.stopTask(
      source: source,
      occurredAtUtc: occurredAtUtc,
    );
    quickEntry.close();
    await _applySnapshot(latestSnapshot, notify: true);
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
      case WindowRole.about:
        if (_activeRole == WindowRole.about) {
          _activeRole = null;
        }
    }
    notifyListeners();
  }

  Future<void> exitRequested() async {
    if (_manualExitInProgress) {
      return;
    }
    _manualExitInProgress = true;
    _deferredSystemUiGeneration += 1;
    _systemStopPromptPending = false;
    _shutdownPreparationStoppedActiveTask = false;
    try {
      final latestSnapshot = await _trackerService.exitRequested();
      await _applyPreparedShutdown(latestSnapshot, notify: false);
      await _bestEffortExitCleanup();
      await _onExit();
    } catch (_) {
      _manualExitInProgress = false;
      rethrow;
    }
  }

  Future<void> _prepareForNativeTermination(
    NativeTerminationOccurrence occurrence,
  ) {
    _terminationPreparationStarted = true;
    _deferredSystemUiGeneration += 1;
    _systemStopPromptPending = false;
    _shutdownPreparationStoppedActiveTask = false;
    _secondaryWindowWarmUpTimer?.cancel();
    return _enqueueSystemEvent(() async {
      await _trackerService.prepareForSystemShutdown(
        occurredAtUtc: occurrence.occurredAtUtc,
      );
    });
  }

  Future<void> _prepareForSystemShutdown({DateTime? occurredAtUtc}) async {
    final beforeSnapshot = await _trackerService.loadSnapshot();
    final latestSnapshot = await _trackerService.exitRequested(
      occurredAtUtc: occurredAtUtc,
    );
    _shutdownPreparationStoppedActiveTask =
        beforeSnapshot.activeTask != null && latestSnapshot.activeTask == null;
    await _applyPreparedShutdown(latestSnapshot, notify: true);
  }

  Future<void> _applyPreparedShutdown(
    AppStateSnapshot snapshot, {
    required bool notify,
  }) async {
    quickEntry.close();
    _activeRole = null;
    await _applySnapshot(snapshot, notify: notify);
  }

  Future<void> _handleShutdownCancelled() async {
    final latestSnapshot = await _trackerService.loadSnapshot();
    final shouldOpenPrompt =
        _shutdownPreparationStoppedActiveTask &&
        latestSnapshot.activeTask == null;
    _shutdownPreparationStoppedActiveTask = false;

    if (!shouldOpenPrompt) {
      await _applySnapshot(latestSnapshot, notify: true);
      return;
    }

    await _openQuickEntry(snapshot: latestSnapshot);
  }

  void _scheduleSystemStopUi() {
    final generation = ++_deferredSystemUiGeneration;
    Timer.run(() {
      unawaited(_runUserAction(() => _applyDeferredSystemStopUi(generation)));
    });
  }

  Future<void> _applyDeferredSystemStopUi(int generation) async {
    if (_shouldSkipDeferredSystemUi(generation)) {
      return;
    }
    final latestSnapshot = _snapshot;
    if (latestSnapshot == null) {
      return;
    }

    quickEntry.close();
    await _applySnapshot(latestSnapshot, notify: true);
    if (_shouldSkipDeferredSystemUi(generation) ||
        !_systemStopPromptPending ||
        latestSnapshot.activeTask != null) {
      return;
    }

    await _openQuickEntry(
      snapshot: latestSnapshot,
      expectedSystemUiGeneration: generation,
      refreshIdleSuggestions: false,
    );
    if (!_shouldSkipDeferredSystemUi(generation) && quickEntry.state.isOpen) {
      _systemStopPromptPending = false;
    }
  }

  void _schedulePreparedShutdownUi() {
    final generation = ++_deferredSystemUiGeneration;
    Timer.run(() {
      unawaited(
        _runUserAction(() => _applyDeferredPreparedShutdownUi(generation)),
      );
    });
  }

  Future<void> _applyDeferredPreparedShutdownUi(int generation) async {
    if (_shouldSkipDeferredSystemUi(generation)) {
      return;
    }
    final latestSnapshot = _snapshot;
    if (latestSnapshot == null) {
      return;
    }
    await _applyPreparedShutdown(latestSnapshot, notify: true);
  }

  void _scheduleShutdownCancellationUi({required bool shouldOpenPrompt}) {
    final generation = ++_deferredSystemUiGeneration;
    Timer.run(() {
      unawaited(
        _runUserAction(
          () => _applyDeferredShutdownCancellationUi(
            generation,
            shouldOpenPrompt: shouldOpenPrompt,
          ),
        ),
      );
    });
  }

  Future<void> _applyDeferredShutdownCancellationUi(
    int generation, {
    required bool shouldOpenPrompt,
  }) async {
    if (_shouldSkipDeferredSystemUi(generation)) {
      return;
    }
    final latestSnapshot = _snapshot;
    if (latestSnapshot == null) {
      return;
    }
    if (!shouldOpenPrompt || latestSnapshot.activeTask != null) {
      await _applySnapshot(latestSnapshot, notify: true);
      return;
    }
    await _openQuickEntry(
      snapshot: latestSnapshot,
      expectedSystemUiGeneration: generation,
      refreshIdleSuggestions: false,
    );
    if (!_shouldSkipDeferredSystemUi(generation) && quickEntry.state.isOpen) {
      _systemStopPromptPending = false;
    }
  }

  bool _shouldSkipDeferredSystemUi(int generation) {
    return _disposed ||
        _terminationInProgress ||
        generation != _deferredSystemUiGeneration;
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
    if (_disposed || _terminationInProgress) {
      return;
    }
    _runtimeErrorMessage = error.toString();
    quickEntry.close();
    _activeRole = WindowRole.quickEntry;
    notifyListeners();
    try {
      await _windowCoordinator.openOrFocus(
        WindowRole.quickEntry,
        configuration: WindowRoleConfiguration.runtimeError(),
      );
      if (_terminationInProgress) {
        _activeRole = null;
        await _closeQuickEntryBestEffort();
      }
    } catch (_) {
      // If the error window cannot be shown, keep the error in controller state
      // so it is still visible if another window is later opened successfully.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _deferredSystemUiGeneration += 1;
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
    _shutdownPreparationStoppedActiveTask = false;
    _systemStopPromptPending = false;
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
          case TrayMenuAction.about:
            await openAbout();
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

  Future<void> _applySnapshot(
    AppStateSnapshot snapshot, {
    required bool notify,
  }) async {
    _snapshot = snapshot;
    await _refreshTray(snapshot);
    _nagScheduler?.update(snapshot);
    if (notify) {
      notifyListeners();
    }
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
    if (_terminationInProgress) {
      return;
    }
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
      if (_terminationInProgress) {
        return;
      }
      try {
        await _windowCoordinator.preload(role);
        if (_terminationInProgress) {
          await _windowCoordinator.close(role);
          return;
        }
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
      if (!_disposed) {
        await handleRuntimeError(error, stackTrace);
      }
    }
  }

  Future<void> _enqueueSystemEvent(Future<void> Function() action) {
    final completion = Completer<void>();
    _systemEventChain = _systemEventChain.then((_) async {
      try {
        await action();
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
        if (!_disposed && !_terminationPreparationStarted) {
          Timer.run(() {
            unawaited(handleRuntimeError(error, stackTrace));
          });
        }
      }
    });
    return completion.future;
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
