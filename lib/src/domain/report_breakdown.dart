import 'report.dart';

enum ReportGroupingMode { task, tags }

final class ReportTagLevel {
  ReportTagLevel(Iterable<String> tagTextNormalizedValues)
    : tagTextNormalizedValues = List.unmodifiable(
        tagTextNormalizedValues.toSet(),
      );

  final List<String> tagTextNormalizedValues;

  @override
  bool operator ==(Object other) {
    return other is ReportTagLevel &&
        _listsEqual(tagTextNormalizedValues, other.tagTextNormalizedValues);
  }

  @override
  int get hashCode => Object.hashAll(tagTextNormalizedValues);
}

final class ReportVisualizationPreferences {
  ReportVisualizationPreferences({
    required this.mode,
    Iterable<ReportTagLevel> tagLevels = const [],
  }) : tagLevels = List.unmodifiable(tagLevels) {
    if (this.tagLevels.length > maxTagLevels) {
      throw ArgumentError.value(
        this.tagLevels.length,
        'tagLevels',
        'At most $maxTagLevels tag levels are supported.',
      );
    }

    final selectedTags = <String>{};
    for (final level in this.tagLevels) {
      for (final tag in level.tagTextNormalizedValues) {
        if (!selectedTags.add(tag)) {
          throw ArgumentError.value(
            tag,
            'tagLevels',
            'A tag can appear in only one level.',
          );
        }
      }
    }
  }

  static const maxTagLevels = 3;
  static final defaults = ReportVisualizationPreferences(
    mode: ReportGroupingMode.task,
  );

  final ReportGroupingMode mode;
  final List<ReportTagLevel> tagLevels;

  ReportVisualizationPreferences copyWith({
    ReportGroupingMode? mode,
    Iterable<ReportTagLevel>? tagLevels,
  }) {
    return ReportVisualizationPreferences(
      mode: mode ?? this.mode,
      tagLevels: tagLevels ?? this.tagLevels,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportVisualizationPreferences &&
        mode == other.mode &&
        _listsEqual(tagLevels, other.tagLevels);
  }

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(tagLevels));
}

final class ReportBreakdown {
  const ReportBreakdown({required this.totalDuration, required this.nodes});

  final Duration totalDuration;
  final List<ReportBreakdownNode> nodes;
}

final class ReportBreakdownNode {
  const ReportBreakdownNode({
    required this.id,
    required this.path,
    required this.label,
    required this.duration,
    this.children = const [],
  });

  final String id;
  final String path;
  final String label;
  final Duration duration;
  final List<ReportBreakdownNode> children;

  double percentageOf(Duration total) {
    if (total.inMicroseconds <= 0) {
      return 0;
    }
    return duration.inMicroseconds / total.inMicroseconds * 100;
  }
}

ReportBreakdown buildReportBreakdown(
  ActivityReport report,
  ReportVisualizationPreferences preferences,
) {
  if (preferences.mode == ReportGroupingMode.task) {
    return _buildTaskBreakdown(report);
  }
  if (preferences.tagLevels.isEmpty ||
      preferences.tagLevels.first.tagTextNormalizedValues.isEmpty) {
    return ReportBreakdown(
      totalDuration: report.totalDuration,
      nodes: const [],
    );
  }

  return ReportBreakdown(
    totalDuration: report.totalDuration,
    nodes: _buildTagLevel(report.rows, preferences.tagLevels, 0, ''),
  );
}

ReportBreakdown _buildTaskBreakdown(ActivityReport report) {
  final sortedRows = report.rows.toList()..sort(_compareRows);
  final visible = sortedRows.take(7).toList();
  final hidden = sortedRows.skip(7).toList();
  final nodes = [
    for (final row in visible)
      ReportBreakdownNode(
        id: 'task:${row.taskTextNormalized}',
        path: 'task:${row.taskTextNormalized}',
        label: row.taskText,
        duration: row.duration,
      ),
    if (hidden.isNotEmpty)
      ReportBreakdownNode(
        id: 'reserved:other',
        path: 'reserved:other',
        label: 'Other',
        duration: hidden.fold(
          Duration.zero,
          (total, row) => total + row.duration,
        ),
      ),
  ];
  return ReportBreakdown(totalDuration: report.totalDuration, nodes: nodes);
}

List<ReportBreakdownNode> _buildTagLevel(
  List<ReportRow> rows,
  List<ReportTagLevel> levels,
  int levelIndex,
  String parentPath,
) {
  if (levelIndex >= levels.length ||
      levels[levelIndex].tagTextNormalizedValues.isEmpty) {
    return const [];
  }

  final selected = levels[levelIndex].tagTextNormalizedValues.toSet();
  final buckets = <String, _TagBucket>{};
  for (final row in rows) {
    final matches = row.tags
        .where((tag) => selected.contains(tag.normalized))
        .toList();
    final bucket = switch (matches.length) {
      0 => const _TagBucketIdentity('reserved:untagged', 'Untagged'),
      1 => _TagBucketIdentity(
        'tag:${matches.single.normalized}',
        matches.single.text,
      ),
      _ => const _TagBucketIdentity('reserved:multiple', 'Multiple'),
    };
    final accumulator = buckets.putIfAbsent(
      bucket.id,
      () => _TagBucket(identity: bucket),
    );
    accumulator.rows.add(row);
    accumulator.duration += row.duration;
  }

  final result = [
    for (final bucket in buckets.values)
      ReportBreakdownNode(
        id: bucket.identity.id,
        path: parentPath.isEmpty
            ? bucket.identity.id
            : '$parentPath/${bucket.identity.id}',
        label: bucket.identity.label,
        duration: bucket.duration,
        children: _buildTagLevel(
          bucket.rows,
          levels,
          levelIndex + 1,
          parentPath.isEmpty
              ? bucket.identity.id
              : '$parentPath/${bucket.identity.id}',
        ),
      ),
  ];
  result.sort(_compareNodes);
  return result;
}

int _compareRows(ReportRow left, ReportRow right) {
  final duration = right.duration.compareTo(left.duration);
  if (duration != 0) {
    return duration;
  }
  return left.taskTextNormalized.compareTo(right.taskTextNormalized);
}

int _compareNodes(ReportBreakdownNode left, ReportBreakdownNode right) {
  final duration = right.duration.compareTo(left.duration);
  if (duration != 0) {
    return duration;
  }
  return left.id.compareTo(right.id);
}

final class _TagBucketIdentity {
  const _TagBucketIdentity(this.id, this.label);

  final String id;
  final String label;
}

final class _TagBucket {
  _TagBucket({required this.identity});

  final _TagBucketIdentity identity;
  final List<ReportRow> rows = [];
  Duration duration = Duration.zero;
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
