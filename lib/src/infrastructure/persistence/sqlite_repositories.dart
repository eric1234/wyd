import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';
import 'app_database.dart';
import 'sqlite_mappers.dart';

final class SqliteActivityLogRepository implements ActivityLogRepository {
  const SqliteActivityLogRepository(
    this._executor, {
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc;

  final DatabaseExecutor _executor;
  final DateTime Function()? _nowUtc;

  @override
  Future<ActivityLogEvent> append(ActivityLogEvent event) async {
    final eventToInsert = _withInsertTimestamp(event);
    final id = await _executor.insert(
      'activity_log',
      activityEventToRow(eventToInsert),
    );
    return eventToInsert.withId(id);
  }

  @override
  Future<List<ActivityLogEvent>> allEvents() async {
    final rows = await _executor.query(
      'activity_log',
      orderBy: 'occurred_at_utc ASC, id ASC',
    );

    return rows.map(activityEventFromRow).toList();
  }

  @override
  Future<ActivityLogEvent?> latestEvent() async {
    final rows = await _executor.query(
      'activity_log',
      orderBy: 'occurred_at_utc DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return activityEventFromRow(rows.single);
  }

  @override
  Future<List<ActivityLogEvent>> taskEventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async {
    final rows = await _executor.query(
      'activity_log',
      where:
          'event_type IN (?, ?) AND occurred_at_utc >= ? AND occurred_at_utc <= ?',
      whereArgs: [
        ActivityEventType.startTask.storageName,
        ActivityEventType.switchTask.storageName,
        serializeUtc(fromUtc),
        serializeUtc(throughUtc),
      ],
      orderBy: 'occurred_at_utc ASC, id ASC',
    );

    return rows.map(activityEventFromRow).toList();
  }

  ActivityLogEvent _withInsertTimestamp(ActivityLogEvent event) {
    return ActivityLogEvent(
      id: event.id,
      occurredAtUtc: event.occurredAtUtc,
      eventType: event.eventType,
      taskText: event.taskText,
      taskTextNormalized: event.taskTextNormalized,
      source: event.source,
      createdAtUtc: (_nowUtc?.call() ?? DateTime.now()).toUtc(),
    );
  }
}

final class SqliteRuntimeStateRepository implements RuntimeStateRepository {
  const SqliteRuntimeStateRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<RuntimeState> read() async {
    final rows = await _executor.query(
      'app_state',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (rows.isEmpty) {
      return RuntimeState();
    }

    final row = rows.single;
    if (row['pending_prompt_expired'] == 1 &&
        row['pending_prompt_shown_at_utc'] == null) {
      throw StateError('Persisted prompt state is invalid.');
    }

    return runtimeStateFromRow(row);
  }

  @override
  Future<void> save(RuntimeState state) async {
    await _executor.insert(
      'app_state',
      runtimeStateToRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final class SqliteSettingsRepository implements SettingsRepository {
  const SqliteSettingsRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<AppSettings> read() async {
    final rows = await _executor.query(
      'settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (rows.isEmpty) {
      return AppSettings.defaults;
    }

    final settings = settingsFromRow(rows.single);
    final issues = settings.validate();
    if (issues.isNotEmpty) {
      throw StateError(
        'Persisted settings are invalid: '
        '${issues.map((issue) => issue.message).join(', ')}',
      );
    }

    return settings;
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _executor.insert(
      'settings',
      settingsToRow(settings),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final class SqliteAppTransaction implements AppTransaction {
  SqliteAppTransaction(DatabaseExecutor executor)
    : activityLog = SqliteActivityLogRepository(executor),
      runtimeState = SqliteRuntimeStateRepository(executor),
      settings = SqliteSettingsRepository(executor);

  @override
  final ActivityLogRepository activityLog;

  @override
  final RuntimeStateRepository runtimeState;

  @override
  final SettingsRepository settings;
}

final class SqliteTransactionRunner implements TransactionRunner {
  const SqliteTransactionRunner(this._database);

  final AppDatabase _database;

  @override
  Future<T> run<T>(Future<T> Function(AppTransaction transaction) action) {
    return _database.transaction((transaction) {
      return action(SqliteAppTransaction(transaction));
    });
  }
}
