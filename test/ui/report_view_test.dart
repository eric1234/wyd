import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/report/report.dart';
import 'package:wyd/src/ui/wyd_app.dart';

void main() {
  testWidgets('shows empty report state', (tester) async {
    final loader = _FakeReportLoader();
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      expect(find.text('No tracked time.'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('shows daily total and rows', (tester) async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: const [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: Duration(minutes: 90),
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      expect(find.text('Total: 1h 30m'), findsOneWidget);
      expect(find.text('Write docs'), findsOneWidget);
      expect(find.text('1h 30m'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('does not overflow with high text scaling', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final configuration = WindowRoleConfiguration.forRole(WindowRole.report);
    await tester.binding.setSurfaceSize(
      Size(configuration.width, configuration.height),
    );
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: const [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: Duration(minutes: 90),
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        _scaledMaterialApp(home: ReportView(controller: controller)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Total: 1h 30m'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('disables next-day navigation for today', (tester) async {
    final loader = _FakeReportLoader();
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      final nextButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(nextButton.onPressed, isNull);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('selects a Monday-start weekly report range', (tester) async {
    final loader = _FakeReportLoader();
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      await tester.tap(find.byType(DropdownButtonFormField<ReportRangePreset>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week').last);
      await tester.pumpAndSettle();

      expect(find.text('2025-12-29 - 2026-01-02'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('previous and next buttons navigate date ranges', (tester) async {
    final loader = _FakeReportLoader();
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
      await tester.pump();
      expect(find.text('2026-01-01'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await tester.pump();
      expect(find.text('2026-01-02'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('shows error state', (tester) async {
    final loader = _FakeReportLoader(error: StateError('report failed'));
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(home: ReportView(controller: controller)),
      );

      expect(find.text('Unable to load report.'), findsOneWidget);
      expect(find.textContaining('report failed'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  test('refreshForShow reloads a fresh report snapshot', () async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 30),
        rows: const [
          ReportRow(
            taskText: 'Old task',
            taskTextNormalized: 'old task',
            duration: Duration(minutes: 30),
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();
    loader.report = ActivityReport(
      totalDuration: const Duration(minutes: 45),
      rows: const [
        ReportRow(
          taskText: 'Fresh task',
          taskTextNormalized: 'fresh task',
          duration: Duration(minutes: 45),
        ),
      ],
    );

    controller.refreshForShow();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.report!.rows.single.taskText, 'Fresh task');
    expect(controller.state.report!.totalDuration, const Duration(minutes: 45));
    controller.dispose();
  });
}

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ReportController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

Widget _scaledMaterialApp({required Widget home}) {
  return MaterialApp(
    theme: buildWydTheme(),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: home,
  );
}

final class _FakeReportLoader implements ActivityReportLoader {
  _FakeReportLoader({this.report, this.error});

  ActivityReport? report;
  Object? error;

  @override
  DateTime todayLocalDate() => DateTime(2026, 1, 2);

  @override
  Future<ActivityReport> loadReport(ReportDateRange dateRange) async {
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return report ??
        ActivityReport(totalDuration: Duration.zero, rows: const []);
  }
}
