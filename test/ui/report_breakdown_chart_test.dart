import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/report/report_breakdown_chart.dart';

void main() {
  testWidgets('legend uses indentation and concise nested labels', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_breakdown()));

    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Foo'), findsOneWidget);
    expect(find.text('Boo'), findsOneWidget);
    expect(find.text('Baz'), findsNWidgets(2));
    expect(find.text('Qux'), findsNWidgets(3));
    expect(find.textContaining(' / '), findsNothing);
    expect(find.text('L1'), findsNothing);
    expect(find.text('L2'), findsNothing);
  });

  testWidgets('same level two tag shares a unique color across parents', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_breakdown()));

    Color colorFor(String path) {
      final marker = tester.widget<Container>(
        find.byKey(ValueKey('report-breakdown-color-$path')),
      );
      return (marker.decoration! as BoxDecoration).color!;
    }

    final barBaz = colorFor('tag:bar/tag:baz');
    final fooBaz = colorFor('tag:foo/tag:baz');
    final barBoo = colorFor('tag:bar/tag:boo');

    expect(barBaz, fooBaz);
    expect(barBoo, isNot(barBaz));
    expect(colorFor('tag:bar'), isNot(barBaz));
  });

  testWidgets('same level three tag shares a unique color across parents', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_breakdown()));

    Color colorFor(String path) {
      final marker = tester.widget<Container>(
        find.byKey(ValueKey('report-breakdown-color-$path')),
      );
      return (marker.decoration! as BoxDecoration).color!;
    }

    final barBooQux = colorFor('tag:bar/tag:boo/tag:qux');
    final fooBazQux = colorFor('tag:foo/tag:baz/tag:qux');

    expect(barBooQux, fooBazQux);
    expect(barBooQux, isNot(colorFor('tag:bar/tag:boo')));
  });

  testWidgets('large saturated palettes finish allocating colors', (
    tester,
  ) async {
    final nodes = [
      for (var index = 0; index < 20; index += 1)
        ReportBreakdownNode(
          id: 'tag:root-$index',
          path: 'tag:root-$index',
          label: 'Root $index',
          duration: const Duration(minutes: 1),
          children: [
            ReportBreakdownNode(
              id: 'tag:child-$index',
              path: 'tag:root-$index/tag:child-$index',
              label: 'Child $index',
              duration: const Duration(minutes: 1),
            ),
          ],
        ),
    ];

    await tester.pumpWidget(
      _harness(
        ReportBreakdown(
          totalDuration: const Duration(minutes: 20),
          nodes: nodes,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('report-breakdown-color-tag:root-0')),
      findsOneWidget,
    );
  });

  testWidgets('all three rings show their nested tooltip', (tester) async {
    await tester.pumpWidget(_harness(_breakdown()));
    final chartRect = tester.getRect(
      find.byKey(const ValueKey('report-breakdown-radial-chart')),
    );
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.addPointer(location: chartRect.center),
    );

    final outerOffset = chartRect.shortestSide * 0.31;
    await tester.sendEventToBinding(
      mouse.hover(chartRect.center + Offset(outerOffset, -outerOffset)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-breakdown-tooltip')),
        matching: find.text('Bar'),
      ),
      findsOneWidget,
    );

    final middleOffset = chartRect.shortestSide * 0.22;
    await tester.sendEventToBinding(
      mouse.hover(chartRect.center + Offset(middleOffset, -middleOffset)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-breakdown-tooltip')),
        matching: find.text('Bar / Boo'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('% of Bar'), findsOneWidget);

    final innerOffset = chartRect.shortestSide * 0.13;
    await tester.sendEventToBinding(
      mouse.hover(chartRect.center + Offset(innerOffset, -innerOffset)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-breakdown-tooltip')),
        matching: find.text('Bar / Boo / Qux'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('% of Boo'), findsOneWidget);

    await tester.sendEventToBinding(mouse.removePointer());
  });
}

Widget _harness(ReportBreakdown breakdown) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: ReportBreakdownVisualization(breakdown: breakdown),
        ),
      ),
    ),
  );
}

ReportBreakdown _breakdown() {
  return ReportBreakdown(
    totalDuration: const Duration(minutes: 4),
    nodes: const [
      ReportBreakdownNode(
        id: 'tag:bar',
        path: 'tag:bar',
        label: 'Bar',
        duration: Duration(minutes: 3),
        children: [
          ReportBreakdownNode(
            id: 'tag:boo',
            path: 'tag:bar/tag:boo',
            label: 'Boo',
            duration: Duration(minutes: 2),
            children: [
              ReportBreakdownNode(
                id: 'tag:qux',
                path: 'tag:bar/tag:boo/tag:qux',
                label: 'Qux',
                duration: Duration(minutes: 2),
              ),
            ],
          ),
          ReportBreakdownNode(
            id: 'tag:baz',
            path: 'tag:bar/tag:baz',
            label: 'Baz',
            duration: Duration(minutes: 1),
            children: [
              ReportBreakdownNode(
                id: 'tag:qux',
                path: 'tag:bar/tag:baz/tag:qux',
                label: 'Qux',
                duration: Duration(minutes: 1),
              ),
            ],
          ),
        ],
      ),
      ReportBreakdownNode(
        id: 'tag:foo',
        path: 'tag:foo',
        label: 'Foo',
        duration: Duration(minutes: 1),
        children: [
          ReportBreakdownNode(
            id: 'tag:baz',
            path: 'tag:foo/tag:baz',
            label: 'Baz',
            duration: Duration(minutes: 1),
            children: [
              ReportBreakdownNode(
                id: 'tag:qux',
                path: 'tag:foo/tag:baz/tag:qux',
                label: 'Qux',
                duration: Duration(minutes: 1),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
