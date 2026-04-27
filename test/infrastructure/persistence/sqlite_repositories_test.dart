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

        final activeTask = TaskLifecycle.deriveActiveTask(
          await repository.allEvents(),
        );

        expect(activeTask, isNotNull);
        expect(activeTask!.taskText, 'Fix bug');
      },
    );
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
          autocompleteLookbackDays: 10,
          responseTimeoutMinutes: 5,
          typingDeferralSeconds: 0,
          startAtLogin: true,
        ),
      );

      final settings = await repository.read();

      expect(settings.reminderIntervalMinutes, 20);
      expect(settings.autocompleteLookbackDays, 10);
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
