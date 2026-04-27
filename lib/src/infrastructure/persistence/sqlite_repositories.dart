import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';
import 'app_database.dart';
import 'sqlite_mappers.dart';

final class SqliteActivityLogRepository implements ActivityLogRepository {
  const SqliteActivityLogRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<ActivityLogEvent> append(ActivityLogEvent event) async {
    final id = await _executor.insert(
      'activity_log',
      activityEventToRow(event),
    );
    return event.withId(id);
  }

  @override
  Future<List<ActivityLogEvent>> allEvents() async {
    final rows = await _executor.query(
      'activity_log',
      orderBy: 'occurred_at_utc ASC, id ASC',
    );

    return rows.map(activityEventFromRow).toList();
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

    return runtimeStateFromRow(rows.single);
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

    return settingsFromRow(rows.single);
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
