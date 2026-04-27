import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';
import 'package:wyd/src/ui/report/report.dart';

void main() {
  group('ReportService', () {
    test('loads daily report from persisted activity rows', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final day = DateTime(2026, 1, 2);
      await harness.activityLog.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime(2026, 1, 2, 9).toUtc(),
          taskText: 'Write docs',
        ),
      );
      await harness.activityLog.append(
        ActivityLogEvent.stopTask(
          occurredAtUtc: DateTime(2026, 1, 2, 10, 30).toUtc(),
          source: ActivitySource.manualStop,
        ),
      );

      final report = await harness.reportService.loadDailyReport(day);

      expect(report.totalDuration, const Duration(minutes: 90));
      expect(report.rows.single.taskText, 'Write docs');
      expect(report.rows.single.duration, const Duration(minutes: 90));
    });
  });

  group('ReportController', () {
    test('opens today and prevents future navigation', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);

      await controller.open();
      await controller.nextDay();

      expect(
        controller.state.selectedDate,
        harness.reportService.todayLocalDate(),
      );
      expect(controller.state.canGoNext, isFalse);
    });

    test('navigates previous and next day', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);
      final today = harness.reportService.todayLocalDate();

      await controller.open();
      await controller.previousDay();
      expect(
        controller.state.selectedDate,
        DateTime(today.year, today.month, today.day - 1),
      );
      expect(controller.state.canGoNext, isTrue);

      await controller.nextDay();
      expect(controller.state.selectedDate, today);
    });

    test('keeps report snapshot static while already open', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);
      final today = harness.reportService.todayLocalDate();

      await controller.open();
      expect(controller.state.report!.rows, isEmpty);
      await harness.activityLog.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime(
            today.year,
            today.month,
            today.day,
            9,
          ).toUtc(),
          taskText: 'Late addition',
        ),
      );

      await controller.open();

      expect(controller.state.report!.rows, isEmpty);
    });
  });
}

final class _Harness {
  _Harness({
    required this.database,
    required this.activityLog,
    required this.reportService,
  });

  final AppDatabase database;
  final SqliteActivityLogRepository activityLog;
  final ReportService reportService;

  static Future<_Harness> create() async {
    final database = await AppDatabase.openInMemory(
      databaseFactory: databaseFactoryFfi,
    );
    final reportService = ReportService(
      transactions: SqliteTransactionRunner(database),
      clock: _FakeClock(DateTime.utc(2026, 1, 2, 18)),
    );
    return _Harness(
      database: database,
      activityLog: SqliteActivityLogRepository(database.database),
      reportService: reportService,
    );
  }

  Future<void> dispose() => database.close();
}

final class _FakeClock implements Clock {
  const _FakeClock(this.current);

  final DateTime current;

  @override
  DateTime nowUtc() => current;
}
