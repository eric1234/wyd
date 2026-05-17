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
      expect(
        indexes.map((row) => row['name']),
        contains('idx_activity_log_occurred_id'),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_activity_log_event_type_occurred'),
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
