import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/domain.dart';
import '../layout_metrics.dart';
import 'report_controller.dart';

class ReportView extends StatefulWidget {
  const ReportView({super.key, required this.controller});

  final ReportController controller;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  ReportState _state = const ReportState();

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(ReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _controllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = _state.report;
    final selection = _state.selection;
    final dateRange = _state.dateRange;
    final rowKeyPrefix = dateRange == null
        ? 'report'
        : '${dateRange.startLocalDateInclusive.toIso8601String()}-'
              '${dateRange.endLocalDateExclusive.toIso8601String()}';
    final metrics = WydLayoutMetrics.of(context);
    final sectionGap = metrics.space(0.75);

    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: SafeArea(
        child: Padding(
          padding: metrics.insetsAll(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RangePresetSelector(
                value: selection?.preset ?? ReportRangePreset.day,
                loading: _state.loading,
                onChanged: widget.controller.selectPreset,
              ),
              SizedBox(height: metrics.space(0.25)),
              _DateHeader(
                title: dateRange == null
                    ? 'Report'
                    : _formatRange(dateRange, _state.today),
                loading: _state.loading,
                canGoNext: _state.canGoNext,
                onPrevious: widget.controller.previousWindow,
                onNext: widget.controller.nextWindow,
              ),
              SizedBox(height: metrics.space(0.5)),
              if (_state.loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_state.errorMessage != null)
                Expanded(
                  child: _ReportStatus(
                    icon: Icons.error_outline,
                    title: 'Unable to load report.',
                    message: _state.errorMessage!,
                  ),
                )
              else if (report == null || report.rows.isEmpty)
                const Expanded(
                  child: _ReportStatus(
                    icon: Icons.timer_off_outlined,
                    title: 'No tracked time.',
                    message: 'Tracked time for this range will appear here.',
                  ),
                )
              else ...[
                _TotalCard(duration: report.totalDuration),
                SizedBox(height: sectionGap),
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: report.rows.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = report.rows[index];
                        return _ReportRowTile(
                          key: ValueKey(
                            '$rowKeyPrefix-${row.taskTextNormalized}',
                          ),
                          row: row,
                          controller: widget.controller,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _controllerChanged() {
    if (mounted) {
      setState(() => _state = widget.controller.state);
    }
  }
}

class _RangePresetSelector extends StatelessWidget {
  const _RangePresetSelector({
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  final ReportRangePreset value;
  final bool loading;
  final ValueChanged<ReportRangePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ReportRangePreset>(
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Range',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: ReportRangePreset.values
          .map(
            (preset) => DropdownMenuItem(
              value: preset,
              child: Text(_presetLabel(preset)),
            ),
          )
          .toList(),
      onChanged: loading
          ? null
          : (preset) {
              if (preset != null) {
                onChanged(preset);
              }
            },
    );
  }
}

class _ReportRowTile extends StatefulWidget {
  const _ReportRowTile({
    required this.row,
    required this.controller,
    super.key,
  });

  final ReportRow row;
  final ReportController controller;

  @override
  State<_ReportRowTile> createState() => _ReportRowTileState();
}

class _ReportRowTileState extends State<_ReportRowTile> {
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _tagFocusNode = FocusNode();

  bool _adding = false;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _tagFocusNode.addListener(_tagFocusChanged);
  }

  @override
  void dispose() {
    _tagFocusNode.removeListener(_tagFocusChanged);
    _tagFocusNode.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);
    final textTheme = Theme.of(context).textTheme;
    final chips = <Widget>[
      for (final tag in widget.row.tags)
        InputChip(
          label: Text(tag.text),
          onDeleted: _submitting ? null : () => unawaited(_removeTag(tag)),
          deleteButtonTooltipMessage: 'Remove tag ${tag.text}',
        ),
      _adding ? _buildTagInput(context, metrics) : _buildAddChip(),
    ];

    return Padding(
      padding: metrics.insetsAll(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.row.taskText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
              ),
              SizedBox(width: metrics.space(1)),
              Text(
                formatReportDuration(widget.row.duration),
                style: textTheme.bodyMedium,
              ),
            ],
          ),
          SizedBox(height: metrics.space(0.5)),
          Wrap(
            spacing: metrics.space(0.5),
            runSpacing: metrics.space(0.25),
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildAddChip() {
    return ActionChip(
      avatar: const Icon(Icons.add),
      label: const Text('Add tag'),
      onPressed: _submitting ? null : _startAdding,
    );
  }

  Widget _buildTagInput(BuildContext context, WydLayoutMetrics metrics) {
    return SizedBox(
      width: metrics.maxWidth(12, min: 160),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CancelTagInputIntent(),
        },
        child: Actions(
          actions: {
            _CancelTagInputIntent: CallbackAction<_CancelTagInputIntent>(
              onInvoke: (_) {
                _cancelAdding();
                return null;
              },
            ),
          },
          child: TextField(
            controller: _tagController,
            focusNode: _tagFocusNode,
            autofocus: true,
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'New tag',
              errorText: _errorText,
              suffixIcon: _submitting
                  ? Padding(
                      padding: metrics.insetsAll(0.75),
                      child: const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Add tag',
                      onPressed: () => unawaited(_submitTag()),
                      icon: const Icon(Icons.check),
                    ),
            ),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => unawaited(_submitTag()),
          ),
        ),
      ),
    );
  }

  void _startAdding() {
    setState(() {
      _adding = true;
      _errorText = null;
      _tagController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tagFocusNode.requestFocus();
      }
    });
  }

  void _cancelAdding() {
    if (!_adding || _submitting) {
      return;
    }

    setState(() {
      _adding = false;
      _errorText = null;
      _tagController.clear();
    });
  }

  Future<void> _submitTag() async {
    if (_submitting) {
      return;
    }

    late final TaskTag draft;
    try {
      draft = TaskTag.fromInput(_tagController.text);
    } on TaskTagValidationException catch (error) {
      setState(() => _errorText = error.message);
      return;
    }

    final duplicate = widget.row.tags.any(
      (tag) => tag.normalized == draft.normalized,
    );
    if (duplicate) {
      setState(() => _errorText = 'Tag already exists.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await widget.controller.addTag(
        taskTextNormalized: widget.row.taskTextNormalized,
        tagText: draft.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _adding = false;
        _submitting = false;
        _tagController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _errorText = error.toString();
      });
    }
  }

  Future<void> _removeTag(TaskTag tag) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.controller.removeTag(
        taskTextNormalized: widget.row.taskTextNormalized,
        tag: tag,
      );
      if (!mounted) {
        return;
      }
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Removed tag "${tag.text}".'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_restoreTag(tag)),
          ),
        ),
      );
    } catch (error) {
      _showSnackBar('Unable to remove tag: $error');
    }
  }

  Future<void> _restoreTag(TaskTag tag) async {
    try {
      await widget.controller.addTag(
        taskTextNormalized: widget.row.taskTextNormalized,
        tagText: tag.text,
      );
    } catch (error) {
      _showSnackBar('Unable to restore tag: $error');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _tagFocusChanged() {
    if (!_tagFocusNode.hasFocus &&
        _adding &&
        !_submitting &&
        _tagController.text.isEmpty) {
      _cancelAdding();
    }
  }
}

final class _CancelTagInputIntent extends Intent {
  const _CancelTagInputIntent();
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.title,
    required this.loading,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final bool loading;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: metrics.insetsSymmetric(horizontal: 0.5, vertical: 0.25),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous period',
              onPressed: loading ? null : onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Next period',
              onPressed: loading || !canGoNext ? null : onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: metrics.insetsAll(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tracked in range',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SizedBox(height: metrics.space(0.25)),
            Text(
              'Total: ${formatReportDuration(duration)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportStatus extends StatelessWidget {
  const _ReportStatus({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = WydLayoutMetrics.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: metrics.maxWidth(22.5, min: 360)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: metrics.size(3), color: colorScheme.secondary),
            SizedBox(height: metrics.space(0.75)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: metrics.space(0.25)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatReportDuration(Duration duration) {
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

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatRange(ReportDateRange range, DateTime? today) {
  final start = range.startLocalDateInclusive;
  var end = DateTime(
    range.endLocalDateExclusive.year,
    range.endLocalDateExclusive.month,
    range.endLocalDateExclusive.day - 1,
  );
  if (today != null && end.isAfter(today)) {
    end = today;
  }
  if (start == end) {
    return _formatDate(start);
  }
  return '${_formatDate(start)} - ${_formatDate(end)}';
}

String _presetLabel(ReportRangePreset preset) => switch (preset) {
  ReportRangePreset.day => 'Day',
  ReportRangePreset.week => 'Week',
  ReportRangePreset.month => 'Month',
  ReportRangePreset.quarter => 'Quarter',
  ReportRangePreset.year => 'Year',
};
