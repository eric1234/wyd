import '../domain/domain.dart';
import 'app_state_snapshot.dart';
import 'clock.dart';
import 'diagnostic_logger.dart';
import 'repositories.dart';
import 'single_writer.dart';
import 'tracking_session.dart';

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
      final transition = (await _loadTrackingSession(
        transaction,
      )).submitTask(taskText: taskText, nowUtc: nowUtc);
      await _applyTransition(transaction, transition);
      _logger.debug('submitTask ${transition.diagnosticAction}');
    });
  }

  Future<AppStateSnapshot> stopTask({
    ActivitySource source = ActivitySource.manualStop,
    DateTime? occurredAtUtc,
  }) {
    return _stateChangingOperation((transaction, nowUtc) async {
      final stopOccurredAtUtc = occurredAtUtc?.toUtc() ?? nowUtc;
      final transition = (await _loadTrackingSession(transaction)).stopTask(
        nowUtc: stopOccurredAtUtc,
        source: source,
        createdAtUtc: nowUtc,
      );
      await _applyTransition(transaction, transition);
    });
  }

  Future<AppStateSnapshot> exitRequested() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final transition = (await _loadTrackingSession(
        transaction,
      )).exitRequested(nowUtc: nowUtc);
      await _applyTransition(transaction, transition);
    });
  }

  Future<AppStateSnapshot> nagPromptShown() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final transition = (await _loadTrackingSession(
        transaction,
      )).nagPromptShown(nowUtc: nowUtc);
      await _applyTransition(transaction, transition);
    });
  }

  Future<AppStateSnapshot> nagPromptTimedOut() {
    return _stateChangingOperation((transaction, nowUtc) async {
      final transition = (await _loadTrackingSession(
        transaction,
      )).nagPromptTimedOut(nowUtc: nowUtc);
      await _applyTransition(transaction, transition);
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
      final transition = (await _loadTrackingSession(
        transaction,
      )).recoverOnStartup(nowUtc: nowUtc);
      await _applyTransition(transaction, transition);
    });
  }

  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(String query) {
    return _singleWriter.run(() async {
      return _transactions.run((transaction) async {
        final settings = await transaction.settings.read();
        final nowUtc = _clock.nowUtc();
        final events = await transaction.activityLog.taskEventsBetween(
          fromUtc: nowUtc.subtract(
            Duration(days: settings.autocompleteLookbackDays),
          ),
          throughUtc: nowUtc,
        );
        return ActivityTimeline(events).autocompleteSuggestions(
          query: query,
          nowUtc: nowUtc,
          lookbackDays: settings.autocompleteLookbackDays,
        );
      });
    });
  }

  Future<TrackingSession> _loadTrackingSession(
    AppTransaction transaction,
  ) async {
    final latestEvent = await transaction.activityLog.latestEvent();
    return TrackingSession(
      timeline: ActivityTimeline([?latestEvent]),
      runtimeState: await transaction.runtimeState.read(),
    );
  }

  Future<void> _applyTransition(
    AppTransaction transaction,
    TrackingTransition transition,
  ) async {
    final event = transition.eventToAppend;
    if (event != null) {
      await transaction.activityLog.append(event);
    }
    if (transition.saveRuntimeState) {
      await transaction.runtimeState.save(transition.runtimeState);
    }
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
    final settings = await transaction.settings.read();
    final nowUtc = _clock.nowUtc();
    final recentTaskEvents = await transaction.activityLog.taskEventsBetween(
      fromUtc: nowUtc.subtract(
        Duration(days: settings.autocompleteLookbackDays),
      ),
      throughUtc: nowUtc,
    );

    return AppStateSnapshot(
      activeTask: _activeTaskFromLatestEvent(
        await transaction.activityLog.latestEvent(),
      ),
      runtimeState: await transaction.runtimeState.read(),
      settings: settings,
      capabilities: _capabilities,
      recentSuggestions: ActivityTimeline(recentTaskEvents)
          .autocompleteSuggestions(
            query: suggestionQuery,
            nowUtc: nowUtc,
            lookbackDays: settings.autocompleteLookbackDays,
          ),
    );
  }

  ActiveTask? _activeTaskFromLatestEvent(ActivityLogEvent? event) {
    if (event == null || !event.opensTask || !event.hasTaskText) {
      return null;
    }

    return ActiveTask.fromEvent(event);
  }
}
