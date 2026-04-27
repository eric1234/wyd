import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
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
    final activeTask = TaskLifecycle.deriveActiveTask(
      await repository.allEvents(),
    );

    expect(activeTask, isNotNull);
    expect(activeTask!.taskText, 'Persistent task');
  });
}
