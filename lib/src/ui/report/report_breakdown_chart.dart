import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/domain.dart';

class ReportBreakdownVisualization extends StatefulWidget {
  const ReportBreakdownVisualization({super.key, required this.breakdown});

  final ReportBreakdown breakdown;

  @override
  State<ReportBreakdownVisualization> createState() =>
      _ReportBreakdownVisualizationState();
}

class _ReportBreakdownVisualizationState
    extends State<ReportBreakdownVisualization> {
  String? _highlightedPath;
  Offset? _tooltipPosition;

  @override
  Widget build(BuildContext context) {
    final palette = _ReportChartPalette.resolve(
      Theme.of(context).brightness,
      widget.breakdown.nodes,
    );
    final segments = _buildSegments(widget.breakdown, palette);
    final highlighted = segments
        .where((segment) => segment.node.path == _highlightedPath)
        .firstOrNull;

    return Column(
      children: [
        Expanded(
          child: _InteractiveRadialChart(
            breakdown: widget.breakdown,
            segments: segments,
            highlighted: highlighted,
            tooltipPosition: _tooltipPosition,
            onHighlightChanged: _setHighlight,
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final segment in segments)
                _BreakdownLegendRow(
                  key: ValueKey('report-breakdown-legend-${segment.node.path}'),
                  segment: segment,
                  totalDuration: widget.breakdown.totalDuration,
                  highlighted: segment.node.path == _highlightedPath,
                  onHighlightChanged: (highlighted) {
                    _setHighlight(highlighted ? segment : null, null);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _setHighlight(_ReportChartSegment? segment, Offset? position) {
    final nextPath = segment?.node.path;
    if (_highlightedPath == nextPath && _tooltipPosition == position) {
      return;
    }
    setState(() {
      _highlightedPath = nextPath;
      _tooltipPosition = position;
    });
  }
}

class _InteractiveRadialChart extends StatelessWidget {
  const _InteractiveRadialChart({
    required this.breakdown,
    required this.segments,
    required this.highlighted,
    required this.tooltipPosition,
    required this.onHighlightChanged,
  });

  final ReportBreakdown breakdown;
  final List<_ReportChartSegment> segments;
  final _ReportChartSegment? highlighted;
  final Offset? tooltipPosition;
  final void Function(_ReportChartSegment? segment, Offset? position)
  onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onHover: (event) {
            onHighlightChanged(
              _hitTestSegment(event.localPosition, size, segments),
              event.localPosition,
            );
          },
          onExit: (_) => onHighlightChanged(null, null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              onHighlightChanged(
                _hitTestSegment(details.localPosition, size, segments),
                details.localPosition,
              );
            },
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('report-breakdown-radial-chart'),
                    painter: _ReportBreakdownPainter(
                      segments: segments,
                      highlightedPath: highlighted?.node.path,
                      separatorColor: Theme.of(context).colorScheme.surface,
                      highlightColor: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Center(
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatVisualizationDuration(breakdown.totalDuration),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text('tracked'),
                        Text(
                          'Total: ${_formatVisualizationDuration(breakdown.totalDuration)}',
                          style: const TextStyle(fontSize: 0),
                        ),
                      ],
                    ),
                  ),
                ),
                if (highlighted != null && tooltipPosition != null)
                  _ChartTooltip(
                    segment: highlighted!,
                    totalDuration: breakdown.totalDuration,
                    pointerPosition: tooltipPosition!,
                    availableSize: size,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({
    required this.segment,
    required this.totalDuration,
    required this.pointerPosition,
    required this.availableSize,
  });

  static const _width = 210.0;
  static const _estimatedHeight = 86.0;

  final _ReportChartSegment segment;
  final Duration totalDuration;
  final Offset pointerPosition;
  final Size availableSize;

  @override
  Widget build(BuildContext context) {
    final preferredLeft = pointerPosition.dx + 12;
    final left =
        (preferredLeft + _width <= availableSize.width - 8
                ? preferredLeft
                : math.max(8.0, pointerPosition.dx - _width - 12))
            .toDouble();
    final top = (pointerPosition.dy + 12)
        .clamp(8.0, math.max(8.0, availableSize.height - _estimatedHeight - 8))
        .toDouble();
    final totalPercentage = segment.node.percentageOf(totalDuration);
    final parentPercentage = segment.parentDuration == null
        ? null
        : segment.node.percentageOf(segment.parentDuration!);
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: left,
      top: top,
      width: _width,
      child: IgnorePointer(
        child: Material(
          key: const ValueKey('report-breakdown-tooltip'),
          elevation: 6,
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: colorScheme.onInverseSurface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    segment.displayPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_formatVisualizationDuration(segment.node.duration)} · '
                    '${totalPercentage.toStringAsFixed(1)}% of total',
                  ),
                  if (parentPercentage != null)
                    Text(
                      '${parentPercentage.toStringAsFixed(1)}% of '
                      '${segment.parentLabel}',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BreakdownLegendRow extends StatelessWidget {
  const _BreakdownLegendRow({
    required this.segment,
    required this.totalDuration,
    required this.highlighted,
    required this.onHighlightChanged,
    super.key,
  });

  final _ReportChartSegment segment;
  final Duration totalDuration;
  final bool highlighted;
  final ValueChanged<bool> onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    final percentage = segment.node.percentageOf(totalDuration);
    return Focus(
      onFocusChange: onHighlightChanged,
      child: MouseRegion(
        onEnter: (_) => onHighlightChanged(true),
        onExit: (_) => onHighlightChanged(false),
        child: Semantics(
          button: true,
          label:
              '${segment.displayPath}, ${_formatVisualizationDuration(segment.node.duration)}, ${percentage.toStringAsFixed(1)} percent of total',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: EdgeInsets.fromLTRB(segment.depth * 18, 3, 0, 3),
            decoration: BoxDecoration(
              color: highlighted
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Container(
                  key: ValueKey('report-breakdown-color-${segment.node.path}'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: segment.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    segment.legendLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: segment.depth == 0
                        ? const TextStyle(fontWeight: FontWeight.w600)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${_formatVisualizationDuration(segment.node.duration)}  '
                    '${percentage.toStringAsFixed(1)}%',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportBreakdownPainter extends CustomPainter {
  const _ReportBreakdownPainter({
    required this.segments,
    required this.highlightedPath,
    required this.separatorColor,
    required this.highlightColor,
  });

  final List<_ReportChartSegment> segments;
  final String? highlightedPath;
  final Color separatorColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = math
        .max(0.0, math.min(size.width, size.height) / 2 - 5)
        .toDouble();
    final separatorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = separatorColor;

    for (final segment in segments) {
      final path = _segmentPath(center, maxRadius, segment);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = segment.color,
      );
      canvas.drawPath(path, separatorPaint);
    }

    final highlighted = segments
        .where((segment) => segment.node.path == highlightedPath)
        .firstOrNull;
    if (highlighted != null) {
      canvas.drawPath(
        _segmentPath(center, maxRadius, highlighted),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = highlightColor,
      );
    }
  }

  @override
  bool shouldRepaint(_ReportBreakdownPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.highlightedPath != highlightedPath ||
        oldDelegate.separatorColor != separatorColor ||
        oldDelegate.highlightColor != highlightColor;
  }
}

Path _segmentPath(
  Offset center,
  double maxRadius,
  _ReportChartSegment segment,
) {
  final outerRadius = maxRadius * segment.outerRadiusFactor;
  final innerRadius = maxRadius * segment.innerRadiusFactor;
  final startAngle = -math.pi / 2 + segment.startAngleOffset;
  final endAngle = startAngle + segment.sweepAngle;
  final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
  final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
  return Path()
    ..moveTo(
      center.dx + math.cos(startAngle) * outerRadius,
      center.dy + math.sin(startAngle) * outerRadius,
    )
    ..arcTo(outerRect, startAngle, segment.sweepAngle, false)
    ..lineTo(
      center.dx + math.cos(endAngle) * innerRadius,
      center.dy + math.sin(endAngle) * innerRadius,
    )
    ..arcTo(innerRect, endAngle, -segment.sweepAngle, false)
    ..close();
}

_ReportChartSegment? _hitTestSegment(
  Offset position,
  Size size,
  List<_ReportChartSegment> segments,
) {
  final center = size.center(Offset.zero);
  final delta = position - center;
  final maxRadius = math
      .max(0.0, math.min(size.width, size.height) / 2 - 5)
      .toDouble();
  if (maxRadius <= 0) {
    return null;
  }
  final radiusFactor = delta.distance / maxRadius;
  final angleOffset = _normalizeAngle(
    math.atan2(delta.dy, delta.dx) + math.pi / 2,
  );
  for (final segment in segments.reversed) {
    if (radiusFactor < segment.innerRadiusFactor ||
        radiusFactor > segment.outerRadiusFactor) {
      continue;
    }
    if (angleOffset >= segment.startAngleOffset &&
        angleOffset <= segment.startAngleOffset + segment.sweepAngle) {
      return segment;
    }
  }
  return null;
}

double _normalizeAngle(double angle) {
  final normalized = angle % (2 * math.pi);
  return normalized < 0 ? normalized + 2 * math.pi : normalized;
}

List<_ReportChartSegment> _buildSegments(
  ReportBreakdown breakdown,
  _ReportChartPalette palette,
) {
  if (breakdown.totalDuration.inMicroseconds <= 0) {
    return const [];
  }
  final maxDepth = _maximumDepth(breakdown.nodes);
  final segments = <_ReportChartSegment>[];
  var rootStart = 0.0;
  for (final root in breakdown.nodes) {
    final rootSweep =
        root.duration.inMicroseconds /
        breakdown.totalDuration.inMicroseconds *
        2 *
        math.pi;
    _appendSegments(
      segments: segments,
      node: root,
      depth: 0,
      maxDepth: maxDepth,
      startAngleOffset: rootStart,
      sweepAngle: rootSweep,
      totalDuration: breakdown.totalDuration,
      displayPath: root.label,
      palette: palette,
    );
    rootStart += rootSweep;
  }
  return segments;
}

void _appendSegments({
  required List<_ReportChartSegment> segments,
  required ReportBreakdownNode node,
  required int depth,
  required int maxDepth,
  required double startAngleOffset,
  required double sweepAngle,
  required Duration totalDuration,
  required String displayPath,
  required _ReportChartPalette palette,
  ReportBreakdownNode? parent,
}) {
  final radii = _ringRadii(depth, maxDepth);
  segments.add(
    _ReportChartSegment(
      node: node,
      displayPath: displayPath,
      legendLabel: node.label,
      depth: depth,
      startAngleOffset: startAngleOffset,
      sweepAngle: sweepAngle,
      innerRadiusFactor: radii.$1,
      outerRadiusFactor: radii.$2,
      color: palette.colorFor(node.path),
      parentLabel: parent?.label,
      parentDuration: parent?.duration,
    ),
  );

  var childStart = startAngleOffset;
  for (final child in node.children) {
    final childSweep =
        child.duration.inMicroseconds /
        totalDuration.inMicroseconds *
        2 *
        math.pi;
    _appendSegments(
      segments: segments,
      node: child,
      depth: depth + 1,
      maxDepth: maxDepth,
      startAngleOffset: childStart,
      sweepAngle: childSweep,
      totalDuration: totalDuration,
      displayPath: '$displayPath / ${child.label}',
      palette: palette,
      parent: node,
    );
    childStart += childSweep;
  }
}

int _maximumDepth(List<ReportBreakdownNode> nodes) {
  var maximum = 0;
  for (final node in nodes) {
    if (node.children.isNotEmpty) {
      maximum = math.max(maximum, 1 + _maximumDepth(node.children));
    }
  }
  return maximum;
}

(double, double) _ringRadii(int depth, int maxDepth) {
  if (maxDepth == 0) {
    return (0.5, 0.98);
  }
  if (maxDepth == 1) {
    return depth == 0 ? (0.72, 0.98) : (0.42, 0.68);
  }

  return switch (depth) {
    0 => (0.76, 0.98),
    1 => (0.52, 0.72),
    _ => (0.28, 0.48),
  };
}

final class _ReportChartSegment {
  const _ReportChartSegment({
    required this.node,
    required this.displayPath,
    required this.legendLabel,
    required this.depth,
    required this.startAngleOffset,
    required this.sweepAngle,
    required this.innerRadiusFactor,
    required this.outerRadiusFactor,
    required this.color,
    this.parentLabel,
    this.parentDuration,
  });

  final ReportBreakdownNode node;
  final String displayPath;
  final String legendLabel;
  final int depth;
  final double startAngleOffset;
  final double sweepAngle;
  final double innerRadiusFactor;
  final double outerRadiusFactor;
  final Color color;
  final String? parentLabel;
  final Duration? parentDuration;
}

final class _ReportChartPalette {
  const _ReportChartPalette(this._colorsByPath);

  final Map<String, Color> _colorsByPath;

  factory _ReportChartPalette.resolve(
    Brightness brightness,
    List<ReportBreakdownNode> roots,
  ) {
    final colors = <String, Color>{};
    final usedHues = <double>[];
    final sortedRoots = roots.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final root in sortedRoots) {
      final hue = _allocateHue(_stableHash(root.path) % 360.0, usedHues);
      usedHues.add(hue);
      final rootColor = HSLColor.fromAHSL(
        1,
        hue,
        0.66,
        brightness == Brightness.dark ? 0.62 : 0.42,
      ).toColor();
      colors[root.path] = rootColor;
    }

    final pathsByDepthAndIdentity = <(int, String), List<String>>{};
    void collectDescendants(ReportBreakdownNode node, int depth) {
      for (final child in node.children) {
        pathsByDepthAndIdentity
            .putIfAbsent((depth + 1, child.id), () => [])
            .add(child.path);
        collectDescendants(child, depth + 1);
      }
    }

    for (final root in roots) {
      collectDescendants(root, 0);
    }
    final descendantIdentities = pathsByDepthAndIdentity.keys.toList()
      ..sort((left, right) {
        final depthComparison = left.$1.compareTo(right.$1);
        return depthComparison != 0
            ? depthComparison
            : left.$2.compareTo(right.$2);
      });
    for (final key in descendantIdentities) {
      final hue = _allocateHue(
        _stableHash('level-${key.$1 + 1}:${key.$2}') % 360.0,
        usedHues,
      );
      usedHues.add(hue);
      final color = HSLColor.fromAHSL(
        1,
        hue,
        math.max(0.58, 0.76 - key.$1 * 0.08),
        brightness == Brightness.dark
            ? math.min(0.82, 0.66 + key.$1 * 0.08)
            : math.min(0.70, 0.50 + key.$1 * 0.08),
      ).toColor();
      for (final path in pathsByDepthAndIdentity[key]!) {
        colors[path] = color;
      }
    }
    return _ReportChartPalette(colors);
  }

  Color colorFor(String path) => _colorsByPath[path] ?? Colors.grey;
}

double _allocateHue(double seed, List<double> usedHues) {
  const minimumDistance = 28.0;
  const maximumAttempts = 16;
  const goldenAngle = 137.508;
  var candidate = seed;
  var bestCandidate = seed;
  var bestDistance = -1.0;
  for (var attempt = 0; attempt < maximumAttempts; attempt += 1) {
    final nearestDistance = usedHues.isEmpty
        ? 360.0
        : usedHues
              .map((usedHue) => _hueDistance(usedHue, candidate))
              .reduce((left, right) => math.min(left, right).toDouble());
    if (nearestDistance >= minimumDistance) {
      return candidate;
    }
    if (nearestDistance > bestDistance) {
      bestDistance = nearestDistance;
      bestCandidate = candidate;
    }
    candidate = (candidate + goldenAngle) % 360;
  }
  return bestCandidate;
}

double _hueDistance(double left, double right) {
  final difference = (left - right).abs();
  return math.min(difference, 360 - difference);
}

int _stableHash(String identity) {
  var hash = 0;
  for (final codeUnit in identity.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash;
}

String _formatVisualizationDuration(Duration duration) {
  if (duration > Duration.zero && duration.inMinutes == 0) {
    return '<1m';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return '${minutes}m';
  }
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}
