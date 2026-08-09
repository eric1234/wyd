import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  test('task grouping keeps seven tasks and combines the remainder', () {
    final report = ActivityReport(
      totalDuration: const Duration(minutes: 360),
      rows: [
        for (var index = 1; index <= 8; index += 1)
          ReportRow(
            taskText: 'Task $index',
            taskTextNormalized: 'task $index',
            duration: Duration(minutes: 90 - (index * 10)),
          ),
      ],
    );

    final breakdown = buildReportBreakdown(
      report,
      ReportVisualizationPreferences.defaults,
    );

    expect(breakdown.nodes, hasLength(8));
    expect(breakdown.nodes.last.label, 'Other');
    expect(breakdown.nodes.last.duration, const Duration(minutes: 10));
  });

  test('tag grouping assigns untagged, exact, and multiple once', () {
    final client = TaskTag.fromInput('Client');
    final review = TaskTag.fromInput('Review');
    final report = ActivityReport(
      totalDuration: const Duration(hours: 3),
      rows: [
        _row('Exact', tags: [client]),
        _row('None'),
        _row('Both', tags: [client, review]),
      ],
    );
    final preferences = ReportVisualizationPreferences(
      mode: ReportGroupingMode.tags,
      tagLevels: [
        ReportTagLevel(['client', 'review']),
      ],
    );

    final breakdown = buildReportBreakdown(report, preferences);

    expect(breakdown.nodes.map((node) => node.label).toSet(), {
      'Client',
      'Multiple',
      'Untagged',
    });
    expect(
      breakdown.nodes.fold(
        Duration.zero,
        (total, node) => total + node.duration,
      ),
      report.totalDuration,
    );
  });

  test('two tag levels conserve each parent duration', () {
    final client = TaskTag.fromInput('Client');
    final internal = TaskTag.fromInput('Internal');
    final build = TaskTag.fromInput('Build');
    final review = TaskTag.fromInput('Review');
    final report = ActivityReport(
      totalDuration: const Duration(hours: 4),
      rows: [
        _row('A', tags: [client, build]),
        _row('B', tags: [client, review]),
        _row('C', tags: [internal]),
        _row('D'),
      ],
    );
    final preferences = ReportVisualizationPreferences(
      mode: ReportGroupingMode.tags,
      tagLevels: [
        ReportTagLevel(['client', 'internal']),
        ReportTagLevel(['build', 'review']),
      ],
    );

    final breakdown = buildReportBreakdown(report, preferences);

    for (final parent in breakdown.nodes) {
      expect(
        parent.children.fold(
          Duration.zero,
          (total, child) => total + child.duration,
        ),
        parent.duration,
      );
    }
  });

  test('three tag levels build a conserving hierarchy', () {
    final client = TaskTag.fromInput('Client');
    final internal = TaskTag.fromInput('Internal');
    final build = TaskTag.fromInput('Build');
    final review = TaskTag.fromInput('Review');
    final planned = TaskTag.fromInput('Planned');
    final urgent = TaskTag.fromInput('Urgent');
    final report = ActivityReport(
      totalDuration: const Duration(hours: 4),
      rows: [
        _row('A', tags: [client, build, planned]),
        _row('B', tags: [client, review, urgent]),
        _row('C', tags: [internal, planned]),
        _row('D'),
      ],
    );
    final preferences = ReportVisualizationPreferences(
      mode: ReportGroupingMode.tags,
      tagLevels: [
        ReportTagLevel(['client', 'internal']),
        ReportTagLevel(['build', 'review']),
        ReportTagLevel(['planned', 'urgent']),
      ],
    );

    final breakdown = buildReportBreakdown(report, preferences);

    for (final parent in breakdown.nodes) {
      expect(_childrenDuration(parent), parent.duration);
      for (final child in parent.children) {
        expect(_childrenDuration(child), child.duration);
      }
    }
    expect(
      breakdown.nodes
          .expand((node) => node.children)
          .expand((node) => node.children),
      isNotEmpty,
    );
  });

  test('preferences reject duplicate tags across levels', () {
    expect(
      () => ReportVisualizationPreferences(
        mode: ReportGroupingMode.tags,
        tagLevels: [
          ReportTagLevel(['client']),
          ReportTagLevel(['client']),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('empty first tag level produces no chart nodes', () {
    final report = ActivityReport(
      totalDuration: const Duration(hours: 1),
      rows: [_row('Task')],
    );

    final breakdown = buildReportBreakdown(
      report,
      ReportVisualizationPreferences(
        mode: ReportGroupingMode.tags,
        tagLevels: [ReportTagLevel(const [])],
      ),
    );

    expect(breakdown.nodes, isEmpty);
    expect(breakdown.totalDuration, report.totalDuration);
  });
}

ReportRow _row(String task, {List<TaskTag> tags = const []}) {
  return ReportRow(
    taskText: task,
    taskTextNormalized: task.toLowerCase(),
    duration: const Duration(hours: 1),
    tags: tags,
  );
}

Duration _childrenDuration(ReportBreakdownNode node) {
  return node.children.fold(
    Duration.zero,
    (total, child) => total + child.duration,
  );
}
