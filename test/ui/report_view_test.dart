import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/report/report.dart';

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
      report: DailyReport(
        localDate: DateTime(2026, 1, 2),
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

  testWidgets('previous and next buttons navigate dates', (tester) async {
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
}

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ReportController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

final class _FakeReportLoader implements DailyReportLoader {
  _FakeReportLoader({this.report, this.error});

  final DailyReport? report;
  final Object? error;

  @override
  DateTime todayLocalDate() => DateTime(2026, 1, 2);

  @override
  Future<DailyReport> loadDailyReport(DateTime localDate) async {
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return report ??
        DailyReport(
          localDate: localDate,
          totalDuration: Duration.zero,
          rows: const [],
        );
  }
}
