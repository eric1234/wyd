import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('persists active task across database reopen', (tester) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'wyd_db_smoke_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');

    final firstDatabase = await AppDatabase.openAtPath(databasePath);
    try {
      final repository = SqliteActivityLogRepository(firstDatabase.database);
      await repository.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Persistent task',
        ),
      );
    } finally {
      await firstDatabase.close();
    }

    final secondDatabase = await AppDatabase.openAtPath(databasePath);
    addTearDown(secondDatabase.close);
    final repository = SqliteActivityLogRepository(secondDatabase.database);
    final activeTask = ActivityTimeline(
      await repository.allEvents(),
    ).activeTask;

    expect(activeTask, isNotNull);
    expect(activeTask!.taskText, 'Persistent task');
  });

  testWidgets('commits lifecycle boundary before database reopen', (
    tester,
  ) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'wyd_boundary_smoke_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final databasePath = p.join(tempDirectory.path, 'wyd.sqlite');
    final database = await AppDatabase.openAtPath(databasePath);
    final clock = _FixedClock(DateTime.utc(2026, 1, 1, 10));
    final service = TrackerService(
      transactions: SqliteTransactionRunner(database),
      clock: clock,
    );
    await service.submitTask('Persistent task');
    await service.applyBoundary(
      source: ActivitySource.exit,
      occurredAtUtc: DateTime.utc(2026, 1, 1, 10, 30),
      cleanShutdown: true,
    );
    await database.close();

    final reopened = await AppDatabase.openAtPath(databasePath);
    addTearDown(reopened.close);
    final events = await SqliteActivityLogRepository(
      reopened.database,
    ).allEvents();
    final state = await SqliteRuntimeStateRepository(reopened.database).read();

    expect(events.last.source, ActivitySource.exit);
    expect(ActivityTimeline(events).activeTask, isNull);
    expect(state.cleanShutdown, isTrue);
  });
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final DateTime value;
  @override
  DateTime nowUtc() => value;
}
