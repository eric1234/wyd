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
  Future<ActivityLogEvent?> latestEventBefore(DateTime beforeUtc) async {
    final rows = await _executor.query(
      'activity_log',
      where: 'occurred_at_utc < ?',
      whereArgs: [serializeUtc(beforeUtc)],
      orderBy: 'occurred_at_utc DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return activityEventFromRow(rows.single);
  }

  @override
  Future<List<ActivityLogEvent>> eventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  }) async {
    final rows = await _executor.query(
      'activity_log',
      where: 'occurred_at_utc >= ? AND occurred_at_utc <= ?',
      whereArgs: [serializeUtc(fromUtc), serializeUtc(throughUtc)],
      orderBy: 'occurred_at_utc ASC, id ASC',
    );

    return rows.map(activityEventFromRow).toList();
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

final class SqliteTaskTagRepository implements TaskTagRepository {
  const SqliteTaskTagRepository(this._executor, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc;

  final DatabaseExecutor _executor;
  final DateTime Function()? _nowUtc;

  @override
  Future<List<TaskTag>> allTags() async {
    final rows = await _executor.rawQuery('''
SELECT tag_text, tag_text_normalized
FROM task_tags
GROUP BY tag_text_normalized
ORDER BY tag_text_normalized ASC
''');
    return rows.map(taskTagFromRow).toList();
  }

  @override
  Future<Map<String, List<TaskTag>>> tagsForTasks(
    Iterable<String> taskTextNormalizedValues,
  ) async {
    final taskKeys = taskTextNormalizedValues.toSet().toList();
    if (taskKeys.isEmpty) {
      return const {};
    }

    final placeholders = List.filled(taskKeys.length, '?').join(', ');
    final rows = await _executor.query(
      'task_tags',
      where: 'task_text_normalized IN ($placeholders)',
      whereArgs: taskKeys,
      orderBy: 'task_text_normalized ASC, tag_text_normalized ASC',
    );
    final tagsByTask = <String, List<TaskTag>>{};
    for (final row in rows) {
      final taskKey = row['task_text_normalized'] as String;
      tagsByTask.putIfAbsent(taskKey, () => []).add(taskTagFromRow(row));
    }

    return tagsByTask;
  }

  @override
  Future<TaskTag> addTag({
    required String taskTextNormalized,
    required String tagText,
  }) async {
    if (taskTextNormalized.isEmpty) {
      throw ArgumentError.value(
        taskTextNormalized,
        'taskTextNormalized',
        'Task key cannot be empty.',
      );
    }

    final tag = TaskTag.fromInput(tagText);
    await _executor.insert(
      'task_tags',
      taskTagToRow(
        taskTextNormalized: taskTextNormalized,
        tag: tag,
        createdAtUtc: (_nowUtc?.call() ?? DateTime.now()).toUtc(),
      ),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final storedTag = await _tagForTask(
      taskTextNormalized: taskTextNormalized,
      tagTextNormalized: tag.normalized,
    );
    if (storedTag == null) {
      throw StateError('Failed to save task tag.');
    }

    return storedTag;
  }

  @override
  Future<void> removeTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) async {
    await _executor.delete(
      'task_tags',
      where: 'task_text_normalized = ? AND tag_text_normalized = ?',
      whereArgs: [taskTextNormalized, tagTextNormalized],
    );
  }

  Future<TaskTag?> _tagForTask({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) async {
    final rows = await _executor.query(
      'task_tags',
      where: 'task_text_normalized = ? AND tag_text_normalized = ?',
      whereArgs: [taskTextNormalized, tagTextNormalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return taskTagFromRow(rows.single);
  }
}

final class SqliteReportPreferencesRepository
    implements ReportPreferencesRepository {
  const SqliteReportPreferencesRepository(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<ReportVisualizationPreferences> read() async {
    final preferenceRows = await _executor.query(
      'report_preferences',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (preferenceRows.isEmpty) {
      return ReportVisualizationPreferences.defaults;
    }

    final mode = switch (preferenceRows.single['grouping_mode']) {
      'task' => ReportGroupingMode.task,
      'tags' => ReportGroupingMode.tags,
      final value => throw StateError('Invalid report grouping mode: $value'),
    };
    final tagRows = await _executor.query(
      'report_preference_tags',
      orderBy: 'level_index ASC, position ASC',
    );
    final levels = <int, List<String>>{};
    for (final row in tagRows) {
      final level = row['level_index'] as int;
      levels
          .putIfAbsent(level, () => [])
          .add(row['tag_text_normalized'] as String);
    }
    final highestLevel = levels.keys.fold(-1, (highest, value) {
      return value > highest ? value : highest;
    });
    return ReportVisualizationPreferences(
      mode: mode,
      tagLevels: [
        for (var index = 0; index <= highestLevel; index += 1)
          ReportTagLevel(levels[index] ?? const []),
      ],
    );
  }

  @override
  Future<void> save(ReportVisualizationPreferences preferences) async {
    await _executor.insert('report_preferences', {
      'id': 1,
      'grouping_mode': preferences.mode == ReportGroupingMode.task
          ? 'task'
          : 'tags',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _executor.delete('report_preference_tags');
    for (
      var levelIndex = 0;
      levelIndex < preferences.tagLevels.length;
      levelIndex += 1
    ) {
      final level = preferences.tagLevels[levelIndex];
      for (
        var position = 0;
        position < level.tagTextNormalizedValues.length;
        position += 1
      ) {
        await _executor.insert('report_preference_tags', {
          'level_index': levelIndex,
          'tag_text_normalized': level.tagTextNormalizedValues[position],
          'position': position,
        });
      }
    }
  }
}

final class SqliteAppTransaction implements AppTransaction {
  SqliteAppTransaction(DatabaseExecutor executor)
    : activityLog = SqliteActivityLogRepository(executor),
      runtimeState = SqliteRuntimeStateRepository(executor),
      settings = SqliteSettingsRepository(executor),
      taskTags = SqliteTaskTagRepository(executor),
      reportPreferences = SqliteReportPreferencesRepository(executor);

  @override
  final ActivityLogRepository activityLog;

  @override
  final RuntimeStateRepository runtimeState;

  @override
  final SettingsRepository settings;

  @override
  final TaskTagRepository taskTags;

  @override
  final ReportPreferencesRepository reportPreferences;
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
