import '../domain/domain.dart';
import 'app_state_snapshot.dart';
import 'clock.dart';
import 'diagnostic_logger.dart';
import 'repositories.dart';
import 'single_writer.dart';

final class AppSettingsValidationException implements Exception {
  const AppSettingsValidationException(this.issues);

  final List<SettingsValidationIssue> issues;

  @override
  String toString() {
    return 'AppSettingsValidationException: '
        '${issues.map((issue) => issue.message).join(', ')}';
  }
}

final class TrackerService {
  TrackerService({
    required TransactionRunner transactions,
    required Clock clock,
    SingleWriter? singleWriter,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
    PlatformCapabilities capabilities = const PlatformCapabilities(),
  }) : _transactions = transactions,
       _clock = clock,
       _singleWriter = singleWriter ?? SingleWriter(),
       _logger = logger,
       _capabilities = capabilities;

  final TransactionRunner _transactions;
  final Clock _clock;
  final SingleWriter _singleWriter;
  final DiagnosticLogger _logger;
  final PlatformCapabilities _capabilities;

  AppStateSnapshot? _lastSnapshot;

  AppStateSnapshot? get lastSnapshot => _lastSnapshot;

  Future<AppStateSnapshot> loadSnapshot({String suggestionQuery = ''}) {
    return _singleWriter.run(() async {
      final snapshot = await _transactions.run(
        (transaction) => _loadSnapshot(transaction, suggestionQuery),
      );
      _lastSnapshot = snapshot;
      return snapshot;
    });
  }

  Future<AppStateSnapshot> submitTask(String taskText) {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      final decision = TaskLifecycle.submitTask(
        events: events,
        taskText: taskText,
        occurredAtUtc: nowUtc,
        createdAtUtc: nowUtc,
      );

      if (decision.event != null) {
        await transaction.activityLog.append(decision.event!);
      }

      final state = await transaction.runtimeState.read();
      await transaction.runtimeState.save(
        state.copyWith(
          lastConfirmationAtUtc: nowUtc,
          promptState: const PromptState.none(),
          cleanShutdown: false,
        ),
      );

      _logger.debug('submitTask ${decision.action.name}');
    });
  }

  Future<AppStateSnapshot> stopTask({
    ActivitySource source = ActivitySource.manualStop,
  }) {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      final decision = TaskLifecycle.stopTask(
        events: events,
        occurredAtUtc: nowUtc,
        source: source,
        createdAtUtc: nowUtc,
      );

      if (decision.event == null) {
        return;
      }

      await transaction.activityLog.append(decision.event!);
      final state = await transaction.runtimeState.read();
      await transaction.runtimeState.save(
        state.copyWith(
          promptState: const PromptState.none(),
          cleanShutdown: false,
        ),
      );
    });
  }

  Future<AppStateSnapshot> exitRequested() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      final activeTask = TaskLifecycle.deriveActiveTask(events);
      final state = await transaction.runtimeState.read();

      if (activeTask != null &&
          state.promptState.status != PromptStatus.expired) {
        await transaction.activityLog.append(
          ActivityLogEvent.stopTask(
            occurredAtUtc: nowUtc,
            source: ActivitySource.exit,
            createdAtUtc: nowUtc,
          ),
        );
      }

      await transaction.runtimeState.save(
        state.copyWith(
          promptState: const PromptState.none(),
          cleanShutdown: true,
        ),
      );
    });
  }

  Future<AppStateSnapshot> nagPromptShown() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      if (TaskLifecycle.deriveActiveTask(events) == null) {
        return;
      }

      final state = await transaction.runtimeState.read();
      if (state.promptState.isPending) {
        return;
      }

      await transaction.runtimeState.save(
        state.copyWith(
          promptState: PromptState.visible(nowUtc),
          cleanShutdown: false,
        ),
      );
    });
  }

  Future<AppStateSnapshot> nagPromptTimedOut() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      final activeTask = TaskLifecycle.deriveActiveTask(events);
      final state = await transaction.runtimeState.read();
      final shownAtUtc = state.promptState.shownAtUtc;

      if (activeTask == null ||
          shownAtUtc == null ||
          state.promptState.status == PromptStatus.expired) {
        return;
      }

      await transaction.activityLog.append(
        ActivityLogEvent.stopTask(
          occurredAtUtc: shownAtUtc,
          source: ActivitySource.nagTimeout,
          createdAtUtc: nowUtc,
        ),
      );
      await transaction.runtimeState.save(
        state.copyWith(
          promptState: PromptState.expired(shownAtUtc),
          cleanShutdown: false,
        ),
      );
    });
  }

  Future<AppStateSnapshot> promptClosed() {
    return loadSnapshot();
  }

  Future<AppStateSnapshot> updateSettings(AppSettings settings) {
    final issues = settings.validate();
    if (issues.isNotEmpty) {
      throw AppSettingsValidationException(issues);
    }

    return _stateChangingOperation((transaction, _) async {
      await transaction.settings.save(settings);
      final state = await transaction.runtimeState.read();
      await transaction.runtimeState.save(state.copyWith(cleanShutdown: false));
    });
  }

  Future<AppStateSnapshot> recoverOnStartup() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final events = await transaction.activityLog.allEvents();
      final state = await transaction.runtimeState.read();

      if (state.cleanShutdown) {
        await transaction.runtimeState.save(
          state.copyWith(cleanShutdown: false),
        );
        return;
      }

      final activeTask = TaskLifecycle.deriveActiveTask(events);
      if (activeTask != null) {
        final recoveryTimestamp =
            state.promptState.shownAtUtc ??
            state.lastConfirmationAtUtc ??
            activeTask.startedAtUtc;
        await transaction.activityLog.append(
          ActivityLogEvent.stopTask(
            occurredAtUtc: recoveryTimestamp,
            source: ActivitySource.recovery,
            createdAtUtc: nowUtc,
          ),
        );
      }

      await transaction.runtimeState.save(
        state.copyWith(
          promptState: const PromptState.none(),
          cleanShutdown: false,
        ),
      );
    });
  }

  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(String query) {
    return _singleWriter.run(() async {
      return _transactions.run((transaction) async {
        final events = await transaction.activityLog.allEvents();
        final settings = await transaction.settings.read();
        return AutocompleteEngine.suggestions(
          events: events,
          query: query,
          nowUtc: _clock.nowUtc(),
          lookbackDays: settings.autocompleteLookbackDays,
        );
      });
    });
  }

  Future<AppStateSnapshot> _stateChangingOperation(
    Future<void> Function(AppTransaction transaction, DateTime nowUtc) action,
  ) {
    return _singleWriter.run(() async {
      try {
        final snapshot = await _transactions.run((transaction) async {
          final nowUtc = _clock.nowUtc();
          await action(transaction, nowUtc);
          return _loadSnapshot(transaction, '');
        });
        _lastSnapshot = snapshot;
        return snapshot;
      } catch (error, stackTrace) {
        _logger.error('state-changing operation failed', error, stackTrace);
        _lastSnapshot =
            await _loadSnapshotAfterFailure(error) ??
            _lastSnapshot?.copyWith(
              busy: false,
              errorMessage: error.toString(),
            );
        rethrow;
      }
    });
  }

  Future<AppStateSnapshot?> _loadSnapshotAfterFailure(Object error) async {
    try {
      final snapshot = await _transactions.run(
        (transaction) => _loadSnapshot(transaction, ''),
      );
      return snapshot.copyWith(errorMessage: error.toString());
    } catch (snapshotError, stackTrace) {
      _logger.error(
        'failed to load snapshot after operation failure',
        snapshotError,
        stackTrace,
      );
      return null;
    }
  }

  Future<AppStateSnapshot> _loadSnapshot(
    AppTransaction transaction,
    String suggestionQuery,
  ) async {
    final events = await transaction.activityLog.allEvents();
    final settings = await transaction.settings.read();

    return AppStateSnapshot(
      activeTask: TaskLifecycle.deriveActiveTask(events),
      runtimeState: await transaction.runtimeState.read(),
      settings: settings,
      capabilities: _capabilities,
      recentSuggestions: AutocompleteEngine.suggestions(
        events: events,
        query: suggestionQuery,
        nowUtc: _clock.nowUtc(),
        lookbackDays: settings.autocompleteLookbackDays,
      ),
    );
  }
}
