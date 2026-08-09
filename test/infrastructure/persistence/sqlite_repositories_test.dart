import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';

void main() {
  group('AppDatabase migrations', () {
    test('create expected tables and indexes', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);

      final tables = await database.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final indexes = await database.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(tables.map((row) => row['name']), contains('activity_log'));
      expect(tables.map((row) => row['name']), contains('app_state'));
      expect(tables.map((row) => row['name']), contains('settings'));
      expect(tables.map((row) => row['name']), contains('task_tags'));
      expect(tables.map((row) => row['name']), contains('report_preferences'));
      expect(
        tables.map((row) => row['name']),
        contains('report_preference_tags'),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_activity_log_occurred_id'),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_activity_log_event_type_occurred'),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_activity_log_task_occurred'),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_task_tags_tag_text_normalized'),
      );
    });

    test('opens independent connections for the same database path', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
      AppDatabase? first;
      AppDatabase? second;

      try {
        first = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        second = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );

        await second.close();
        second = null;

        final tables = await first.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );

        expect(tables.map((row) => row['name']), contains('activity_log'));
      } finally {
        await second?.close();
        await first?.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('lists database and SQLite sidecar paths', () {
      final databasePath = p.join('tmp', 'wyd.sqlite');

      expect(AppDatabase.databaseFilePathsFor(databasePath), [
        databasePath,
        '$databasePath-wal',
        '$databasePath-shm',
        '$databasePath-journal',
      ]);
    });

    test('deletes database files and ignores missing files', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_delete_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');

      try {
        for (final filePath in AppDatabase.databaseFilePathsFor(databasePath)) {
          await File(filePath).writeAsString('test');
        }

        await AppDatabase.deleteDatabaseFiles(databasePath);
        await AppDatabase.deleteDatabaseFiles(databasePath);

        for (final filePath in AppDatabase.databaseFilePathsFor(databasePath)) {
          expect(await File(filePath).exists(), isFalse);
        }
      } finally {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('reopens as a fresh database after deleting files', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_fresh_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
      AppDatabase? database;
      AppDatabase? freshDatabase;

      try {
        database = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        await SqliteActivityLogRepository(database.database).append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
            taskText: 'Delete me',
          ),
        );
        await database.close();
        database = null;

        await AppDatabase.deleteDatabaseFiles(databasePath);

        freshDatabase = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        final events = await SqliteActivityLogRepository(
          freshDatabase.database,
        ).allEvents();

        expect(events, isEmpty);
      } finally {
        await freshDatabase?.close();
        await database?.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('configures SQLite pragmas for production connections', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_pragmas_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
      AppDatabase? database;

      try {
        database = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );

        final foreignKeys = await database.database.rawQuery(
          'PRAGMA foreign_keys',
        );
        final journalMode = await database.database.rawQuery(
          'PRAGMA journal_mode',
        );
        final busyTimeout = await database.database.rawQuery(
          'PRAGMA busy_timeout',
        );

        expect(foreignKeys.single.values.single, 1);
        expect(journalMode.single.values.single, 'wal');
        expect(busyTimeout.single.values.single, 5000);
      } finally {
        await database?.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('rejects rows that violate schema constraints', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final timestamp = DateTime.utc(2026, 1, 1, 9).toIso8601String();

      Future<void> expectConstraintFailure(Future<void> Function() action) {
        return expectLater(action, throwsA(isA<DatabaseException>()));
      }

      await expectConstraintFailure(() async {
        await database.database.insert('activity_log', {
          'occurred_at_utc': timestamp,
          'event_type': 'unknown',
          'source': 'manual_submit',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('activity_log', {
          'occurred_at_utc': timestamp,
          'event_type': 'stop_task',
          'task_text': 'Should not exist',
          'task_text_normalized': 'should not exist',
          'source': 'manual_stop',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('activity_log', {
          'occurred_at_utc': timestamp,
          'event_type': 'start_task',
          'source': 'manual_submit',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('activity_log', {
          'occurred_at_utc': timestamp,
          'event_type': 'stop_task',
          'source': 'not_a_source',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('app_state', {
          'id': 1,
          'pending_prompt_expired': 2,
          'clean_shutdown': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await expectConstraintFailure(() async {
        await database.database.insert('app_state', {
          'id': 1,
          'pending_prompt_expired': 1,
          'clean_shutdown': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await expectConstraintFailure(() async {
        await database.database.insert('settings', {
          'id': 1,
          'reminder_interval_minutes': 15,
          'autocomplete_lookback_days': 3,
          'response_timeout_minutes': 1,
          'typing_deferral_seconds': 5,
          'start_at_login': 2,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('settings', {
          'id': 1,
          'reminder_interval_minutes': 1,
          'autocomplete_lookback_days': 3,
          'response_timeout_minutes': 2,
          'typing_deferral_seconds': 5,
          'start_at_login': 0,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('settings', {
          'id': 1,
          'reminder_interval_minutes': 15,
          'autocomplete_lookback_days': 366,
          'response_timeout_minutes': 1,
          'typing_deferral_seconds': 5,
          'start_at_login': 0,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('task_tags', {
          'task_text_normalized': '',
          'tag_text': 'Bug',
          'tag_text_normalized': 'bug',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('task_tags', {
          'task_text_normalized': 'fix bug',
          'tag_text': '',
          'tag_text_normalized': 'bug',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('task_tags', {
          'task_text_normalized': 'fix bug',
          'tag_text': ''.padRight(TaskTag.maxLength + 1, 'a'),
          'tag_text_normalized': 'bug',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('task_tags', {
          'task_text_normalized': 'fix bug',
          'tag_text': 'Bug',
          'tag_text_normalized': '',
          'created_at_utc': timestamp,
        });
      });
      await expectConstraintFailure(() async {
        await database.database.insert('task_tags', {
          'task_text_normalized': 'fix bug',
          'tag_text': 'Bug',
          'tag_text_normalized': ''.padRight(TaskTag.maxLength + 1, 'a'),
          'created_at_utc': timestamp,
        });
      });
    });

    test('fails clearly when opening a newer schema version', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_upgrade_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
      AppDatabase? database;

      try {
        database = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        await database.close();
        database = null;

        await expectLater(
          () => AppDatabase.openAtPath(
            databasePath,
            databaseFactory: databaseFactoryFfi,
            schemaVersion: AppDatabase.schemaVersion + 1,
          ),
          throwsA(isA<UnsupportedError>()),
        );
      } finally {
        await database?.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });

    test('migrates version 1 settings autocomplete max', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'wyd_sqlite_v2_migration_',
      );
      final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
      AppDatabase? database;

      try {
        await _createVersion1Database(databasePath);

        database = await AppDatabase.openAtPath(
          databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        final repository = SqliteSettingsRepository(database.database);

        expect((await repository.read()).autocompleteLookbackDays, 30);

        final tables = await database.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        expect(tables.map((row) => row['name']), contains('task_tags'));

        await repository.save(const AppSettings(autocompleteLookbackDays: 365));

        expect((await repository.read()).autocompleteLookbackDays, 365);
      } finally {
        await database?.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });

  group('SqliteReportPreferencesRepository', () {
    test('returns defaults and round trips ordered levels', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final repository = SqliteReportPreferencesRepository(database.database);

      expect(await repository.read(), ReportVisualizationPreferences.defaults);

      final preferences = ReportVisualizationPreferences(
        mode: ReportGroupingMode.tags,
        tagLevels: [
          ReportTagLevel(['client-a', 'client-b']),
          ReportTagLevel(['build', 'review']),
        ],
      );
      await repository.save(preferences);

      expect(await repository.read(), preferences);
    });

    test('replacement removes old selected tags', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final repository = SqliteReportPreferencesRepository(database.database);
      await repository.save(
        ReportVisualizationPreferences(
          mode: ReportGroupingMode.tags,
          tagLevels: [
            ReportTagLevel(['old']),
          ],
        ),
      );

      final replacement = ReportVisualizationPreferences(
        mode: ReportGroupingMode.task,
      );
      await repository.save(replacement);

      expect(await repository.read(), replacement);
      expect(await database.database.query('report_preference_tags'), isEmpty);
    });
  });

  group('SqliteActivityLogRepository', () {
    late AppDatabase database;
    late SqliteActivityLogRepository repository;

    setUp(() async {
      database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      repository = SqliteActivityLogRepository(database.database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'inserts and reads events ordered by occurred_at_utc then id',
      () async {
        final later = await repository.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
            taskText: 'Later task',
          ),
        );
        final earlier = await repository.append(
          ActivityLogEvent.switchTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
            taskText: 'Earlier task',
          ),
        );
        final tie = await repository.append(
          ActivityLogEvent.stopTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
            source: ActivitySource.manualStop,
          ),
        );

        final events = await repository.allEvents();

        expect(events.map((event) => event.id), [earlier.id, later.id, tie.id]);
        expect(events.map((event) => event.occurredAtUtc), [
          DateTime.utc(2026, 1, 1, 9),
          DateTime.utc(2026, 1, 1, 10),
          DateTime.utc(2026, 1, 1, 10),
        ]);
      },
    );

    test('persists nullable task fields for stop events', () async {
      await repository.append(
        ActivityLogEvent.stopTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
          source: ActivitySource.exit,
        ),
      );

      final event = (await repository.allEvents()).single;

      expect(event.eventType, ActivityEventType.stopTask);
      expect(event.taskText, isNull);
      expect(event.taskTextNormalized, isNull);
      expect(event.source, ActivitySource.exit);
    });

    test('only appends rows through the repository API', () async {
      final first = await repository.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'First task',
        ),
      );
      final second = await repository.append(
        ActivityLogEvent.switchTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
          taskText: 'Second task',
        ),
      );

      final events = await repository.allEvents();

      expect(events, hasLength(2));
      expect(first.id, greaterThan(0));
      expect(second.id, greaterThan(first.id));
    });

    test(
      'supports current active task derivation from persisted events',
      () async {
        await repository.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
            taskText: 'Write docs',
          ),
        );
        await repository.append(
          ActivityLogEvent.switchTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
            taskText: 'Fix bug',
          ),
        );

        final activeTask = ActivityTimeline(
          await repository.allEvents(),
        ).activeTask;

        expect(activeTask, isNotNull);
        expect(activeTask!.taskText, 'Fix bug');
      },
    );

    test('reads latest event and bounded task events', () async {
      await repository.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Old task',
        ),
      );
      await repository.append(
        ActivityLogEvent.stopTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
          source: ActivitySource.manualStop,
        ),
      );
      await repository.append(
        ActivityLogEvent.switchTask(
          occurredAtUtc: DateTime.utc(2026, 1, 2, 9),
          taskText: 'Recent task',
        ),
      );

      expect((await repository.latestEvent())!.taskText, 'Recent task');
      expect(
        (await repository.latestEventBefore(
          DateTime.utc(2026, 1, 2),
        ))!.eventType,
        ActivityEventType.stopTask,
      );
      final boundedEvents = await repository.eventsBetween(
        fromUtc: DateTime.utc(2026, 1, 1, 10),
        throughUtc: DateTime.utc(2026, 1, 2, 9),
      );
      expect(boundedEvents.map((event) => event.eventType), [
        ActivityEventType.stopTask,
        ActivityEventType.switchTask,
      ]);

      final taskEvents = await repository.taskEventsBetween(
        fromUtc: DateTime.utc(2026, 1, 2),
        throughUtc: DateTime.utc(2026, 1, 3),
      );

      expect(taskEvents.map((event) => event.taskText), ['Recent task']);
    });
  });

  group('SqliteRuntimeStateRepository', () {
    test('persists and reads runtime state', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final repository = SqliteRuntimeStateRepository(database.database);
      final promptShownAt = DateTime.utc(2026, 1, 1, 10);

      await repository.save(
        RuntimeState(
          lastConfirmationAtUtc: DateTime.utc(2026, 1, 1, 9),
          promptState: PromptState.expired(promptShownAt),
          cleanShutdown: false,
        ),
      );

      final state = await repository.read();

      expect(state.lastConfirmationAtUtc, DateTime.utc(2026, 1, 1, 9));
      expect(state.promptState.status, PromptStatus.expired);
      expect(state.promptState.shownAtUtc, promptShownAt);
      expect(state.cleanShutdown, isFalse);
    });
  });

  group('SqliteSettingsRepository', () {
    test('returns defaults when settings row is missing', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database.database);

      expect(await repository.read(), AppSettings.defaults);
    });

    test('persists settings', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database.database);

      await repository.save(
        const AppSettings(
          reminderIntervalMinutes: 20,
          autocompleteLookbackDays: 365,
          responseTimeoutMinutes: 5,
          typingDeferralSeconds: 0,
          startAtLogin: true,
        ),
      );

      final settings = await repository.read();

      expect(settings.reminderIntervalMinutes, 20);
      expect(settings.autocompleteLookbackDays, 365);
      expect(settings.responseTimeoutMinutes, 5);
      expect(settings.typingDeferralSeconds, 0);
      expect(settings.startAtLogin, isTrue);
    });
  });

  group('SqliteTaskTagRepository', () {
    late AppDatabase database;
    late SqliteTaskTagRepository repository;
    late DateTime nowUtc;

    setUp(() async {
      database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      nowUtc = DateTime.utc(2026, 1, 1, 9);
      repository = SqliteTaskTagRepository(
        database.database,
        nowUtc: () => nowUtc,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('adds, reads, and removes tags for a task', () async {
      final tag = await repository.addTag(
        taskTextNormalized: 'fix login',
        tagText: 'Bug',
      );

      expect(tag, TaskTag.fromInput('Bug'));
      expect(await repository.tagsForTasks(['fix login']), {
        'fix login': [TaskTag.fromInput('Bug')],
      });

      await repository.removeTag(
        taskTextNormalized: 'fix login',
        tagTextNormalized: 'bug',
      );

      expect(await repository.tagsForTasks(['fix login']), isEmpty);
    });

    test('returns multiple tags in normalized order', () async {
      await repository.addTag(taskTextNormalized: 'fix login', tagText: 'Fire');
      await repository.addTag(taskTextNormalized: 'fix login', tagText: 'Bug');

      final tagsByTask = await repository.tagsForTasks(['fix login']);

      expect(tagsByTask['fix login'], [
        TaskTag.fromInput('Bug'),
        TaskTag.fromInput('Fire'),
      ]);
    });

    test(
      'deduplicates normalized tags and returns stored display text',
      () async {
        await repository.addTag(
          taskTextNormalized: 'fix login',
          tagText: 'Bug',
        );

        final tag = await repository.addTag(
          taskTextNormalized: 'fix login',
          tagText: '  bug  ',
        );

        expect(tag.text, 'Bug');
        expect((await repository.tagsForTasks(['fix login']))['fix login'], [
          TaskTag.fromInput('Bug'),
        ]);
      },
    );

    test('batch lookup only returns requested tasks', () async {
      await repository.addTag(taskTextNormalized: 'fix login', tagText: 'Bug');
      await repository.addTag(
        taskTextNormalized: 'write docs',
        tagText: 'Docs',
      );
      await repository.addTag(
        taskTextNormalized: 'support call',
        tagText: 'Support',
      );

      final tagsByTask = await repository.tagsForTasks([
        'write docs',
        'fix login',
      ]);

      expect(tagsByTask.keys, unorderedEquals(['write docs', 'fix login']));
      expect(tagsByTask['fix login'], [TaskTag.fromInput('Bug')]);
      expect(tagsByTask['write docs'], [TaskTag.fromInput('Docs')]);
      expect(tagsByTask.containsKey('support call'), isFalse);
    });

    test(
      'orders tags by latest tracked activity across carrying tasks',
      () async {
        final activityLog = SqliteActivityLogRepository(database.database);
        await activityLog.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 8),
            taskText: 'Old bug task',
          ),
        );
        await activityLog.append(
          ActivityLogEvent.switchTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 11),
            taskText: 'Recent bug task',
          ),
        );
        await activityLog.append(
          ActivityLogEvent.switchTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
            taskText: 'Feature task',
          ),
        );
        await repository.addTag(
          taskTextNormalized: 'old bug task',
          tagText: 'Bug',
        );
        await repository.addTag(
          taskTextNormalized: 'recent bug task',
          tagText: 'BUG',
        );
        await repository.addTag(
          taskTextNormalized: 'feature task',
          tagText: 'Feature',
        );

        expect(await repository.allTags(), [
          TaskTag.fromInput('BUG'),
          TaskTag.fromInput('Feature'),
        ]);
      },
    );

    test('breaks recency ties by tag and newest display assignment', () async {
      final activityLog = SqliteActivityLogRepository(database.database);
      final tiedAt = DateTime.utc(2026, 1, 1, 10);
      await activityLog.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: tiedAt,
          taskText: 'First bug task',
        ),
      );
      await activityLog.append(
        ActivityLogEvent.switchTask(
          occurredAtUtc: tiedAt,
          taskText: 'Second bug task',
        ),
      );
      await activityLog.append(
        ActivityLogEvent.switchTask(
          occurredAtUtc: tiedAt,
          taskText: 'Alpha task',
        ),
      );
      await repository.addTag(
        taskTextNormalized: 'first bug task',
        tagText: 'Bug',
      );
      nowUtc = nowUtc.add(const Duration(minutes: 1));
      await repository.addTag(
        taskTextNormalized: 'second bug task',
        tagText: 'BUG',
      );
      await repository.addTag(
        taskTextNormalized: 'alpha task',
        tagText: 'Alpha',
      );

      expect(await repository.allTags(), [
        TaskTag.fromInput('Alpha'),
        TaskTag.fromInput('BUG'),
      ]);
    });

    test(
      'sorts never-tracked tags last and forgets the final assignment',
      () async {
        final activityLog = SqliteActivityLogRepository(database.database);
        await activityLog.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
            taskText: 'Tracked task',
          ),
        );
        await repository.addTag(
          taskTextNormalized: 'tracked task',
          tagText: 'Tracked',
        );
        await repository.addTag(
          taskTextNormalized: 'missing task z',
          tagText: 'Zulu',
        );
        await repository.addTag(
          taskTextNormalized: 'missing task a',
          tagText: 'Alpha',
        );

        expect(await repository.allTags(), [
          TaskTag.fromInput('Tracked'),
          TaskTag.fromInput('Alpha'),
          TaskTag.fromInput('Zulu'),
        ]);

        await repository.removeTag(
          taskTextNormalized: 'missing task a',
          tagTextNormalized: 'alpha',
        );

        expect(await repository.allTags(), [
          TaskTag.fromInput('Tracked'),
          TaskTag.fromInput('Zulu'),
        ]);
      },
    );
  });

  group('SqliteTransactionRunner', () {
    test('rolls back writes when a transaction fails', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final runner = SqliteTransactionRunner(database);
      final repository = SqliteActivityLogRepository(database.database);

      await expectLater(
        runner.run<void>((transaction) async {
          await transaction.activityLog.append(
            ActivityLogEvent.startTask(
              occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
              taskText: 'Rolled back task',
            ),
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );

      expect(await repository.allEvents(), isEmpty);
    });

    test('rolls back tag writes when a transaction fails', () async {
      final database = await AppDatabase.openInMemory(
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final runner = SqliteTransactionRunner(database);
      final repository = SqliteTaskTagRepository(database.database);

      await expectLater(
        runner.run<void>((transaction) async {
          await transaction.taskTags.addTag(
            taskTextNormalized: 'rolled back task',
            tagText: 'Bug',
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );

      expect(await repository.tagsForTasks(['rolled back task']), isEmpty);
    });
  });
}

Future<void> _createVersion1Database(String databasePath) async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
CREATE TABLE activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  occurred_at_utc TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK(event_type IN ('start_task', 'switch_task', 'stop_task')),
  task_text TEXT,
  task_text_normalized TEXT,
  source TEXT NOT NULL CHECK(source IN (
    'manual_submit',
    'manual_stop',
    'nag_timeout',
    'system_lock',
    'system_sleep',
    'exit',
    'recovery'
  )),
  created_at_utc TEXT NOT NULL,
  CHECK (
    (event_type = 'stop_task' AND task_text IS NULL AND task_text_normalized IS NULL)
    OR
    (event_type IN ('start_task', 'switch_task') AND task_text IS NOT NULL AND task_text_normalized IS NOT NULL)
  )
)
''');
        await database.execute('''
CREATE INDEX idx_activity_log_occurred_id
ON activity_log (occurred_at_utc, id)
''');
        await database.execute('''
CREATE INDEX idx_activity_log_event_type_occurred
ON activity_log (event_type, occurred_at_utc)
''');
        await database.execute('''
CREATE TABLE app_state (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  last_confirmation_at_utc TEXT,
  pending_prompt_shown_at_utc TEXT,
  pending_prompt_expired INTEGER NOT NULL DEFAULT 0 CHECK(pending_prompt_expired IN (0, 1)),
  clean_shutdown INTEGER NOT NULL DEFAULT 1 CHECK(clean_shutdown IN (0, 1)),
  CHECK (pending_prompt_expired = 0 OR pending_prompt_shown_at_utc IS NOT NULL)
)
''');
        await database.insert('app_state', {
          'id': 1,
          'pending_prompt_expired': 0,
          'clean_shutdown': 1,
        });
        await database.execute('''
CREATE TABLE settings (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  reminder_interval_minutes INTEGER NOT NULL CHECK(reminder_interval_minutes BETWEEN 1 AND 240),
  autocomplete_lookback_days INTEGER NOT NULL CHECK(autocomplete_lookback_days BETWEEN 1 AND 30),
  response_timeout_minutes INTEGER NOT NULL CHECK(response_timeout_minutes BETWEEN 1 AND 60),
  typing_deferral_seconds INTEGER NOT NULL CHECK(typing_deferral_seconds BETWEEN 0 AND 30),
  start_at_login INTEGER NOT NULL CHECK(start_at_login IN (0, 1)),
  CHECK (reminder_interval_minutes >= response_timeout_minutes)
)
''');
        await database.insert('settings', {
          'id': 1,
          'reminder_interval_minutes': 15,
          'autocomplete_lookback_days': 30,
          'response_timeout_minutes': 1,
          'typing_deferral_seconds': 5,
          'start_at_login': 0,
        });
      },
    ),
  );

  await database.close();
}
