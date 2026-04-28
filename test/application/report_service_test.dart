import 'dart:async';

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

    test(
      'derives reports from bounded events around the selected day',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final day = DateTime(2026, 1, 1);
        await harness.activityLog.append(
          ActivityLogEvent.startTask(
            occurredAtUtc: DateTime(2025, 12, 31, 20).toUtc(),
            taskText: 'Long task',
          ),
        );
        await harness.activityLog.append(
          ActivityLogEvent.stopTask(
            occurredAtUtc: DateTime(2026, 1, 3).toUtc(),
            source: ActivitySource.manualStop,
          ),
        );

        final report = await harness.reportService.loadDailyReport(day);

        expect(report.totalDuration, const Duration(hours: 24));
        expect(report.rows.single.taskText, 'Long task');
      },
    );
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

    test('ignores stale date load results', () async {
      final loader = _DelayedDailyReportLoader(DateTime(2026, 1, 3));
      final controller = ReportController(loader);
      final firstDate = DateTime(2026, 1, 1);
      final secondDate = DateTime(2026, 1, 2);

      final firstLoad = controller.loadDate(firstDate);
      final secondLoad = controller.loadDate(secondDate);

      expect(loader.requests.map((request) => request.localDate), [
        firstDate,
        secondDate,
      ]);
      loader.complete(1, _report(secondDate, 'Second result'));
      await secondLoad;
      expect(controller.state.selectedDate, secondDate);
      expect(controller.state.report!.rows.single.taskText, 'Second result');

      loader.complete(0, _report(firstDate, 'Stale result'));
      await firstLoad;
      expect(controller.state.selectedDate, secondDate);
      expect(controller.state.report!.rows.single.taskText, 'Second result');
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

final class _DelayedDailyReportLoader implements DailyReportLoader {
  _DelayedDailyReportLoader(this.today);

  final DateTime today;
  final List<_ReportRequest> requests = [];

  @override
  DateTime todayLocalDate() => today;

  @override
  Future<DailyReport> loadDailyReport(DateTime localDate) {
    final request = _ReportRequest(localDate);
    requests.add(request);
    return request.completer.future;
  }

  void complete(int index, DailyReport report) {
    requests[index].completer.complete(report);
  }
}

final class _ReportRequest {
  _ReportRequest(this.localDate);

  final DateTime localDate;
  final Completer<DailyReport> completer = Completer<DailyReport>();
}

DailyReport _report(DateTime localDate, String taskText) {
  return DailyReport(
    localDate: localDate,
    totalDuration: const Duration(minutes: 1),
    rows: [
      ReportRow(
        taskText: taskText,
        taskTextNormalized: taskText.toLowerCase(),
        duration: const Duration(minutes: 1),
      ),
    ],
  );
}
