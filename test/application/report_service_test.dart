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

      final report = await harness.reportService.loadReport(_dayRange(day));

      expect(report.totalDuration, const Duration(minutes: 90));
      expect(report.rows.single.taskText, 'Write docs');
      expect(report.rows.single.duration, const Duration(minutes: 90));
    });

    test('loads task tags with report rows', () async {
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
        ActivityLogEvent.switchTask(
          occurredAtUtc: DateTime(2026, 1, 2, 10).toUtc(),
          taskText: 'write   docs',
        ),
      );
      await harness.taskTags.addTag(
        taskTextNormalized: 'write docs',
        tagText: 'Docs',
      );

      final report = await harness.reportService.loadReport(_dayRange(day));

      expect(report.rows, hasLength(1));
      expect(report.rows.single.taskTextNormalized, 'write docs');
      expect(report.rows.single.tags, [TaskTag.fromInput('Docs')]);
    });

    test('adds and removes tags through the report service', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final day = DateTime(2026, 1, 2);
      await harness.activityLog.append(
        ActivityLogEvent.startTask(
          occurredAtUtc: DateTime(2026, 1, 2, 9).toUtc(),
          taskText: 'Fix bug',
        ),
      );

      await harness.reportService.addTaskTag(
        taskTextNormalized: 'fix bug',
        tagText: 'Bug',
      );

      expect(
        (await harness.reportService.loadReport(
          _dayRange(day),
        )).rows.single.tags,
        [TaskTag.fromInput('Bug')],
      );

      await harness.reportService.removeTaskTag(
        taskTextNormalized: 'fix bug',
        tagTextNormalized: 'bug',
      );

      expect(
        (await harness.reportService.loadReport(
          _dayRange(day),
        )).rows.single.tags,
        isEmpty,
      );
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

        final report = await harness.reportService.loadReport(_dayRange(day));

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
      await controller.nextWindow();

      expect(
        controller.state.selection!.anchorDate,
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
      await controller.previousWindow();
      expect(
        controller.state.selection!.anchorDate,
        DateTime(today.year, today.month, today.day - 1),
      );
      expect(controller.state.canGoNext, isTrue);

      await controller.nextWindow();
      expect(controller.state.selection!.anchorDate, today);
    });

    test('uses Monday-start weeks and navigates calendar weeks', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);

      await controller.open();
      await controller.selectPreset(ReportRangePreset.week);

      expect(
        controller.state.dateRange!.startLocalDateInclusive,
        DateTime(2025, 12, 29),
      );
      expect(
        controller.state.dateRange!.endLocalDateExclusive,
        DateTime(2026, 1, 5),
      );
      expect(controller.state.canGoNext, isFalse);

      await controller.previousWindow();
      expect(
        controller.state.dateRange!.startLocalDateInclusive,
        DateTime(2025, 12, 22),
      );
      expect(controller.state.canGoNext, isTrue);
    });

    test('resolves month quarter and year calendar ranges', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);

      await controller.open();
      await controller.selectPreset(ReportRangePreset.month);
      expect(
        controller.state.dateRange!.startLocalDateInclusive,
        DateTime(2026, 1),
      );
      expect(
        controller.state.dateRange!.endLocalDateExclusive,
        DateTime(2026, 2),
      );

      await controller.selectPreset(ReportRangePreset.quarter);
      expect(
        controller.state.dateRange!.startLocalDateInclusive,
        DateTime(2026, 1),
      );
      expect(
        controller.state.dateRange!.endLocalDateExclusive,
        DateTime(2026, 4),
      );

      await controller.selectPreset(ReportRangePreset.year);
      expect(
        controller.state.dateRange!.startLocalDateInclusive,
        DateTime(2026),
      );
      expect(controller.state.dateRange!.endLocalDateExclusive, DateTime(2027));
    });

    test('preserves the viewed date when switching presets', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);
      final today = harness.reportService.todayLocalDate();

      await controller.open();
      await controller.selectPreset(ReportRangePreset.week);
      await controller.selectPreset(ReportRangePreset.day);

      expect(controller.state.selection!.anchorDate, today);
      expect(controller.state.dateRange!.startLocalDateInclusive, today);
    });

    test('refreshForShow preserves selected day while already open', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);
      final today = harness.reportService.todayLocalDate();
      final previousDay = DateTime(today.year, today.month, today.day - 1);

      await controller.open();
      await controller.previousWindow();
      await controller.refreshForShow();

      expect(controller.state.selection!.anchorDate, previousDay);
      expect(controller.state.isOpen, isTrue);
    });

    test('refreshForShow returns to today after close', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final controller = ReportController(harness.reportService);
      final today = harness.reportService.todayLocalDate();

      await controller.open();
      await controller.previousWindow();
      controller.close();
      await controller.refreshForShow();

      expect(controller.state.selection!.anchorDate, today);
      expect(controller.state.isOpen, isTrue);
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
      final loader = _DelayedActivityReportLoader(DateTime(2026, 1, 3));
      final controller = ReportController(loader);
      final firstDate = DateTime(2026, 1, 1);
      final secondDate = DateTime(2026, 1, 2);

      final firstLoad = controller.loadSelection(
        ReportSelection(preset: ReportRangePreset.day, anchorDate: firstDate),
      );
      final secondLoad = controller.loadSelection(
        ReportSelection(preset: ReportRangePreset.day, anchorDate: secondDate),
      );

      expect(
        loader.requests.map(
          (request) => request.dateRange.startLocalDateInclusive,
        ),
        [firstDate, secondDate],
      );
      loader.complete(1, _report(secondDate, 'Second result'));
      await secondLoad;
      expect(controller.state.selection!.anchorDate, secondDate);
      expect(controller.state.report!.rows.single.taskText, 'Second result');

      loader.complete(0, _report(firstDate, 'Stale result'));
      await firstLoad;
      expect(controller.state.selection!.anchorDate, secondDate);
      expect(controller.state.report!.rows.single.taskText, 'Second result');
    });

    test(
      'close invalidates refresh while visualization load is pending',
      () async {
        final delayedVisualization = Completer<ReportVisualizationData>();
        var visualizationLoads = 0;
        final loader = _StaticActivityReportLoader(
          report: _report(DateTime(2026, 1, 2), 'Task'),
          visualizationLoader: () {
            visualizationLoads += 1;
            if (visualizationLoads == 1) {
              return Future.value(_defaultVisualizationData());
            }
            return delayedVisualization.future;
          },
        );
        final controller = ReportController(loader);
        addTearDown(controller.dispose);
        await controller.open();

        final refresh = controller.refreshForShow();
        controller.close();
        delayedVisualization.complete(_defaultVisualizationData());
        await refresh;

        expect(controller.state.isOpen, isFalse);
      },
    );

    test('older preference failure does not roll back a newer edit', () async {
      final saveRequests = <Completer<void>>[];
      final loader = _StaticActivityReportLoader(
        report: _report(DateTime(2026, 1, 2), 'Task'),
        preferenceSaver: (preferences) {
          final request = Completer<void>();
          saveRequests.add(request);
          return request.future;
        },
      );
      final controller = ReportController(loader);
      addTearDown(controller.dispose);
      await controller.open();

      final firstSave = controller.setGroupingMode(ReportGroupingMode.tags);
      final secondSave = controller.setTagLevel(0, ['client']);
      final latestPreferences = ReportVisualizationPreferences(
        mode: ReportGroupingMode.tags,
        tagLevels: [
          ReportTagLevel(['client']),
        ],
      );
      expect(controller.state.visualizationPreferences, latestPreferences);

      saveRequests.first.completeError(StateError('older save failed'));
      await pumpEventQueue();

      expect(controller.state.visualizationPreferences, latestPreferences);
      expect(controller.state.preferenceErrorMessage, isNull);

      saveRequests.last.complete();
      await Future.wait([firstSave, secondSave]);
      expect(controller.state.visualizationPreferences, latestPreferences);
    });

    test('latest preference failure rolls back to persisted state', () async {
      final saveRequests = <Completer<void>>[];
      final loader = _StaticActivityReportLoader(
        report: _report(DateTime(2026, 1, 2), 'Task'),
        preferenceSaver: (preferences) {
          final request = Completer<void>();
          saveRequests.add(request);
          return request.future;
        },
      );
      final controller = ReportController(loader);
      addTearDown(controller.dispose);
      await controller.open();

      final firstPreferences = ReportVisualizationPreferences(
        mode: ReportGroupingMode.tags,
        tagLevels: [ReportTagLevel(const [])],
      );
      final firstSave = controller.setGroupingMode(ReportGroupingMode.tags);
      saveRequests.first.complete();
      await firstSave;
      expect(controller.state.visualizationPreferences, firstPreferences);

      final secondSave = controller.setTagLevel(0, ['client']);
      saveRequests.last.completeError(StateError('latest save failed'));
      await secondSave;

      expect(controller.state.visualizationPreferences, firstPreferences);
      expect(
        controller.state.preferenceErrorMessage,
        contains('latest save failed'),
      );
    });

    test('updates current report tags after add and remove', () async {
      final client = _StaticActivityReportLoader(
        report: _report(DateTime(2026, 1, 2), 'Fix bug'),
      );
      final controller = ReportController(client);
      addTearDown(controller.dispose);
      await controller.open();

      final tag = await controller.addTag(
        taskTextNormalized: 'fix bug',
        tagText: 'Bug',
      );

      expect(tag, TaskTag.fromInput('Bug'));
      expect(controller.state.report!.rows.single.tags, [
        TaskTag.fromInput('Bug'),
      ]);

      await controller.removeTag(taskTextNormalized: 'fix bug', tag: tag);

      expect(controller.state.report!.rows.single.tags, isEmpty);
    });

    test(
      'tag operation failure does not replace report with error state',
      () async {
        final client = _StaticActivityReportLoader(
          report: _report(DateTime(2026, 1, 2), 'Fix bug'),
          addError: StateError('tag failed'),
        );
        final controller = ReportController(client);
        addTearDown(controller.dispose);
        await controller.open();

        await expectLater(
          controller.addTag(taskTextNormalized: 'fix bug', tagText: 'Bug'),
          throwsStateError,
        );

        expect(controller.state.errorMessage, isNull);
        expect(controller.state.report!.rows.single.taskText, 'Fix bug');
      },
    );
  });
}

final class _Harness {
  _Harness({
    required this.database,
    required this.activityLog,
    required this.taskTags,
    required this.reportService,
  });

  final AppDatabase database;
  final SqliteActivityLogRepository activityLog;
  final SqliteTaskTagRepository taskTags;
  final ReportService reportService;

  static Future<_Harness> create() async {
    final database = await AppDatabase.openInMemory(
      databaseFactory: databaseFactoryFfi,
    );
    final reportService = ReportService(
      transactions: SqliteTransactionRunner(database),
      clock: _FakeClock(DateTime.utc(2026, 1, 4, 12)),
    );
    return _Harness(
      database: database,
      activityLog: SqliteActivityLogRepository(database.database),
      taskTags: SqliteTaskTagRepository(database.database),
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

final class _DelayedActivityReportLoader implements ActivityReportLoader {
  _DelayedActivityReportLoader(this.today);

  final DateTime today;
  final List<_ReportRequest> requests = [];

  @override
  Future<ReportVisualizationData> loadVisualizationData() async {
    return ReportVisualizationData(
      availableTags: const [],
      preferences: ReportVisualizationPreferences.defaults,
    );
  }

  @override
  Future<void> saveVisualizationPreferences(
    ReportVisualizationPreferences preferences,
  ) async {}

  @override
  DateTime todayLocalDate() => today;

  @override
  Future<ActivityReport> loadReport(ReportDateRange dateRange) {
    final request = _ReportRequest(dateRange);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<TaskTag> addTaskTag({
    required String taskTextNormalized,
    required String tagText,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeTaskTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) {
    throw UnimplementedError();
  }

  void complete(int index, ActivityReport report) {
    requests[index].completer.complete(report);
  }
}

final class _StaticActivityReportLoader implements ActivityReportLoader {
  _StaticActivityReportLoader({
    required this.report,
    this.addError,
    this.visualizationLoader,
    this.preferenceSaver,
  });

  final ActivityReport report;
  final Object? addError;
  final Future<ReportVisualizationData> Function()? visualizationLoader;
  final Future<void> Function(ReportVisualizationPreferences preferences)?
  preferenceSaver;

  @override
  Future<ReportVisualizationData> loadVisualizationData() {
    return visualizationLoader?.call() ??
        Future.value(_defaultVisualizationData());
  }

  @override
  Future<void> saveVisualizationPreferences(
    ReportVisualizationPreferences preferences,
  ) {
    return preferenceSaver?.call(preferences) ?? Future.value();
  }

  @override
  DateTime todayLocalDate() => DateTime(2026, 1, 2);

  @override
  Future<ActivityReport> loadReport(ReportDateRange dateRange) async => report;

  @override
  Future<TaskTag> addTaskTag({
    required String taskTextNormalized,
    required String tagText,
  }) async {
    final error = addError;
    if (error != null) {
      throw error;
    }
    return TaskTag.fromInput(tagText);
  }

  @override
  Future<void> removeTaskTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) async {}
}

final class _ReportRequest {
  _ReportRequest(this.dateRange);

  final ReportDateRange dateRange;
  final Completer<ActivityReport> completer = Completer<ActivityReport>();
}

ActivityReport _report(DateTime localDate, String taskText) {
  return ActivityReport(
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

ReportDateRange _dayRange(DateTime date) => ReportDateRange(
  startLocalDateInclusive: date,
  endLocalDateExclusive: DateTime(date.year, date.month, date.day + 1),
);

ReportVisualizationData _defaultVisualizationData() {
  return ReportVisualizationData(
    availableTags: const [],
    preferences: ReportVisualizationPreferences.defaults,
  );
}
