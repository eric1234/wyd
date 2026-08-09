import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      expect(find.text('Write docs'), findsNWidgets(2));
      expect(find.text('1h 30m'), findsNWidgets(2));
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('shows task tags and add tag action', (tester) async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: const Duration(minutes: 90),
            tags: [TaskTag.fromInput('Docs')],
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('Add tag'), findsOneWidget);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('adds a tag from inline input', (tester) async {
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
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Bug');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(loader.addCalls.single.taskTextNormalized, 'write docs');
      expect(loader.addCalls.single.tagText, 'Bug');
      expect(find.text('Bug'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('shows eligible tags and adds a clicked suggestion immediately', (
    tester,
  ) async {
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
      availableTags: [TaskTag.fromInput('Feature'), TaskTag.fromInput('Bug')],
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();

      expect(find.text('Feature'), findsOneWidget);
      expect(find.text('Bug'), findsOneWidget);

      await tester.tap(find.text('Bug'));
      await tester.pumpAndSettle();

      expect(loader.addCalls.single.tagText, 'Bug');
      expect(find.byType(TextField), findsNothing);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('anchors suggestions next to the tag field when opening upward', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1000, 480));
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
      availableTags: [TaskTag.fromInput('Anchored tag')],
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();

      final fieldRect = tester.getRect(find.byType(TextField));
      final optionRect = tester.getRect(find.text('Anchored tag'));
      final verticalGap = [
        (fieldRect.top - optionRect.bottom).abs(),
        (optionRect.top - fieldRect.bottom).abs(),
      ].reduce((left, right) => left < right ? left : right);

      expect(verticalGap, lessThan(32));
      expect((optionRect.left - fieldRect.left).abs(), lessThan(32));
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('arrow and Enter accept a highlighted tag suggestion', (
    tester,
  ) async {
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
      availableTags: [
        TaskTag.fromInput('Debug'),
        TaskTag.fromInput('Bug'),
        TaskTag.fromInput('Build'),
      ],
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bu');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(loader.addCalls.single.tagText, 'Build');
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('Escape dismisses suggestions before custom Enter submit', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1000, 700));
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
      availableTags: [TaskTag.fromInput('Bug'), TaskTag.fromInput('Build')],
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bu');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.binding.setSurfaceSize(const Size(1001, 700));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(loader.addCalls.single.tagText, 'Bu');
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('hides same-level tags but allows manual conflict fallback', (
    tester,
  ) async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: const Duration(minutes: 90),
            tags: [TaskTag.fromInput('Bug')],
          ),
        ],
      ),
      availableTags: [
        TaskTag.fromInput('Feature'),
        TaskTag.fromInput('Docs'),
        TaskTag.fromInput('Bug'),
      ],
      preferences: ReportVisualizationPreferences(
        mode: ReportGroupingMode.task,
        tagLevels: [
          ReportTagLevel(['bug', 'feature']),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();

      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('Feature'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Feature');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(loader.addCalls.single.tagText, 'Feature');
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('keeps tag input open when adding a suggestion fails', (
    tester,
  ) async {
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
      availableTags: [TaskTag.fromInput('Bug')],
      addError: StateError('tag failed'),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bug'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('tag failed'), findsOneWidget);

      loader.addError = null;
      await tester.tap(find.widgetWithText(InkWell, 'Bug'));
      await tester.pumpAndSettle();

      expect(loader.addCalls.single.tagText, 'Bug');
      expect(find.byType(TextField), findsNothing);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('shows inline error for duplicate tag input', (tester) async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: const Duration(minutes: 90),
            tags: [TaskTag.fromInput('Bug')],
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), ' bug ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Tag already exists.'), findsOneWidget);
      expect(loader.addCalls, isEmpty);
    } finally {
      await _disposeWidgetHarness(tester, controller);
    }
  });

  testWidgets('removes a tag with undo snackbar', (tester) async {
    final loader = _FakeReportLoader(
      report: ActivityReport(
        totalDuration: const Duration(minutes: 90),
        rows: [
          ReportRow(
            taskText: 'Write docs',
            taskTextNormalized: 'write docs',
            duration: const Duration(minutes: 90),
            tags: [TaskTag.fromInput('Bug')],
          ),
        ],
      ),
    );
    final controller = ReportController(loader);
    await controller.open();

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWydTheme(),
          home: ReportView(controller: controller),
        ),
      );

      await tester.tap(find.byTooltip('Remove tag Bug'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(loader.removeCalls.single.taskTextNormalized, 'write docs');
      expect(loader.removeCalls.single.tagTextNormalized, 'bug');
      expect(find.text('Removed tag "Bug".'), findsOneWidget);
      expect(find.text('Bug'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(loader.addCalls.single.tagText, 'Bug');
      expect(find.text('Bug'), findsOneWidget);
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

  testWidgets('resets the range dropdown after closing and reopening', (
    tester,
  ) async {
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
      expect(_selectedRange(tester), ReportRangePreset.week);

      controller.close();
      await controller.refreshForShow();
      await tester.pumpAndSettle();

      expect(_selectedRange(tester), ReportRangePreset.day);
      expect(find.text('2026-01-02'), findsOneWidget);
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

    await controller.refreshForShow();

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

ReportRangePreset? _selectedRange(WidgetTester tester) {
  return tester
      .widget<DropdownButtonFormField<ReportRangePreset>>(
        find.byType(DropdownButtonFormField<ReportRangePreset>),
      )
      .initialValue;
}

final class _FakeReportLoader implements ActivityReportLoader {
  _FakeReportLoader({
    this.report,
    this.error,
    this.addError,
    this.availableTags = const [],
    ReportVisualizationPreferences? preferences,
  }) : preferences = preferences ?? ReportVisualizationPreferences.defaults;

  ActivityReport? report;
  Object? error;
  Object? addError;
  final List<TaskTag> availableTags;
  final ReportVisualizationPreferences preferences;
  final List<_AddTagCall> addCalls = [];
  final List<_RemoveTagCall> removeCalls = [];

  @override
  Future<ReportVisualizationData> loadVisualizationData() async {
    return ReportVisualizationData(
      availableTags: availableTags,
      preferences: preferences,
    );
  }

  @override
  Future<void> saveVisualizationPreferences(
    ReportVisualizationPreferences preferences,
  ) async {}

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

  @override
  Future<TaskTag> addTaskTag({
    required String taskTextNormalized,
    required String tagText,
  }) async {
    final error = addError;
    if (error != null) {
      throw error;
    }
    addCalls.add(_AddTagCall(taskTextNormalized, tagText));
    return TaskTag.fromInput(tagText);
  }

  @override
  Future<void> removeTaskTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) async {
    removeCalls.add(_RemoveTagCall(taskTextNormalized, tagTextNormalized));
  }
}

final class _AddTagCall {
  const _AddTagCall(this.taskTextNormalized, this.tagText);

  final String taskTextNormalized;
  final String tagText;
}

final class _RemoveTagCall {
  const _RemoveTagCall(this.taskTextNormalized, this.tagTextNormalized);

  final String taskTextNormalized;
  final String tagTextNormalized;
}
