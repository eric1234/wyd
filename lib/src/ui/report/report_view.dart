import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/domain.dart';
import '../layout_metrics.dart';
import 'report_breakdown_chart.dart';
import 'report_controller.dart';

class ReportView extends StatefulWidget {
  const ReportView({super.key, required this.controller});

  final ReportController controller;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  ReportState _state = const ReportState();
  String? _shownPreferenceError;

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
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final visualization = _VisualizationPane(
                        state: _state,
                        controller: widget.controller,
                      );
                      final taskList = _TaskList(
                        report: report,
                        rowKeyPrefix: rowKeyPrefix,
                        controller: widget.controller,
                      );
                      if (constraints.maxWidth >= 760) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 340, child: visualization),
                            SizedBox(width: sectionGap),
                            Expanded(child: taskList),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 330, child: visualization),
                          SizedBox(height: sectionGap),
                          Expanded(child: taskList),
                        ],
                      );
                    },
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
      final next = widget.controller.state;
      setState(() => _state = next);
      final preferenceError = next.preferenceErrorMessage;
      if (preferenceError != null && preferenceError != _shownPreferenceError) {
        _shownPreferenceError = preferenceError;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(preferenceError)));
          widget.controller.clearPreferenceError();
        });
      }
    }
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.report,
    required this.rowKeyPrefix,
    required this.controller,
  });

  final ActivityReport report;
  final String rowKeyPrefix;
  final ReportController controller;

  @override
  Widget build(BuildContext context) {
    final availableTags = controller.state.availableTags;
    final tagLevels =
        controller.state.visualizationPreferences?.tagLevels ??
        const <ReportTagLevel>[];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: report.rows.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = report.rows[index];
          return _ReportRowTile(
            key: ValueKey('$rowKeyPrefix-${row.taskTextNormalized}'),
            row: row,
            controller: controller,
            availableTags: availableTags,
            tagLevels: tagLevels,
          );
        },
      ),
    );
  }
}

class _VisualizationPane extends StatelessWidget {
  const _VisualizationPane({required this.state, required this.controller});

  final ReportState state;
  final ReportController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);
    final preferences =
        state.visualizationPreferences ??
        ReportVisualizationPreferences.defaults;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: metrics.insetsAll(0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ReportGroupingMode>(
              key: ValueKey(preferences.mode),
              initialValue: preferences.mode,
              decoration: const InputDecoration(
                labelText: 'Group chart by',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: ReportGroupingMode.task,
                  child: Text('Tasks'),
                ),
                DropdownMenuItem(
                  value: ReportGroupingMode.tags,
                  child: Text('Tags'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) unawaited(controller.setGroupingMode(mode));
              },
            ),
            if (preferences.mode == ReportGroupingMode.tags) ...[
              SizedBox(height: metrics.space(0.5)),
              _TagLevelControls(
                preferences: preferences,
                availableTags: state.availableTags,
                controller: controller,
              ),
            ],
            SizedBox(height: metrics.space(0.5)),
            Expanded(
              child: state.breakdown == null
                  ? const SizedBox.shrink()
                  : state.breakdown!.nodes.isEmpty
                  ? Center(
                      child: Text(
                        preferences.mode == ReportGroupingMode.tags
                            ? 'Select tags for level 1 to build the chart.'
                            : 'No chart data.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ReportBreakdownVisualization(breakdown: state.breakdown!),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagLevelControls extends StatelessWidget {
  const _TagLevelControls({
    required this.preferences,
    required this.availableTags,
    required this.controller,
  });

  final ReportVisualizationPreferences preferences;
  final List<TaskTag> availableTags;
  final ReportController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (
          var levelIndex = 0;
          levelIndex < preferences.tagLevels.length;
          levelIndex += 1
        )
          _TagLevelRow(
            levelIndex: levelIndex,
            preferences: preferences,
            availableTags: availableTags,
            controller: controller,
          ),
        if (preferences.tagLevels.length <
            ReportVisualizationPreferences.maxTagLevels)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(controller.addTagLevel()),
              icon: const Icon(Icons.add),
              label: const Text('Add level'),
            ),
          ),
        Text(
          'Tasks with no selected tag use Untagged; tasks matching more than one use Multiple.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TagLevelRow extends StatelessWidget {
  const _TagLevelRow({
    required this.levelIndex,
    required this.preferences,
    required this.availableTags,
    required this.controller,
  });

  final int levelIndex;
  final ReportVisualizationPreferences preferences;
  final List<TaskTag> availableTags;
  final ReportController controller;

  @override
  Widget build(BuildContext context) {
    final selected = preferences.tagLevels[levelIndex].tagTextNormalizedValues;
    final sortedAvailableTags = availableTags.toList()
      ..sort((left, right) => left.normalized.compareTo(right.normalized));
    final usedElsewhere = <String>{
      for (var index = 0; index < preferences.tagLevels.length; index += 1)
        if (index != levelIndex)
          ...preferences.tagLevels[index].tagTextNormalizedValues,
    };
    return Row(
      children: [
        Expanded(
          child: MenuAnchor(
            builder: (context, menuController, child) {
              return OutlinedButton(
                onPressed: menuController.isOpen
                    ? menuController.close
                    : menuController.open,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selected.isEmpty
                        ? 'Level ${levelIndex + 1}: Select tags'
                        : 'Level ${levelIndex + 1}: ${selected.length} selected',
                  ),
                ),
              );
            },
            menuChildren: [
              for (final tag in sortedAvailableTags)
                if (!usedElsewhere.contains(tag.normalized))
                  CheckboxMenuButton(
                    value: selected.contains(tag.normalized),
                    onChanged: (checked) {
                      final next = selected.toList();
                      if (checked ?? false) {
                        next.add(tag.normalized);
                      } else {
                        next.remove(tag.normalized);
                      }
                      unawaited(controller.setTagLevel(levelIndex, next));
                    },
                    child: Text(tag.text),
                  ),
            ],
          ),
        ),
        if (preferences.tagLevels.length > 1)
          IconButton(
            tooltip: 'Remove level ${levelIndex + 1}',
            onPressed: () => unawaited(controller.removeTagLevel(levelIndex)),
            icon: const Icon(Icons.close),
          ),
      ],
    );
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
    required this.availableTags,
    required this.tagLevels,
    super.key,
  });

  final ReportRow row;
  final ReportController controller;
  final List<TaskTag> availableTags;
  final List<ReportTagLevel> tagLevels;

  @override
  State<_ReportRowTile> createState() => _ReportRowTileState();
}

class _ReportRowTileState extends State<_ReportRowTile> {
  final _TagTextEditingController _tagController = _TagTextEditingController();
  final FocusNode _tagFocusNode = FocusNode();

  bool _adding = false;
  bool _submitting = false;
  bool _suggestionsDismissed = false;
  bool _refreshingAutocomplete = false;
  int _autocompleteRevision = 0;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _tagController.addListener(_tagControllerChanged);
    _tagFocusNode.addListener(_tagFocusChanged);
  }

  @override
  void didUpdateWidget(_ReportRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final suggestionsChanged =
        !listEquals(oldWidget.row.tags, widget.row.tags) ||
        !listEquals(oldWidget.availableTags, widget.availableTags) ||
        !listEquals(oldWidget.tagLevels, widget.tagLevels);
    if (_adding && !_submitting && suggestionsChanged) {
      _autocompleteRevision += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _adding && !_submitting) {
          _refreshAutocomplete();
        }
      });
    }
  }

  @override
  void dispose() {
    _tagController.removeListener(_tagControllerChanged);
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
      child: RawAutocomplete<TaskTag>(
        key: ValueKey(_autocompleteRevision),
        textEditingController: _tagController,
        focusNode: _tagFocusNode,
        displayStringForOption: (tag) => tag.text,
        optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
        optionsBuilder: (value) {
          if (_submitting || _suggestionsDismissed) {
            return const Iterable<TaskTag>.empty();
          }
          return widget.controller.tagSuggestions(
            assignedTags: widget.row.tags,
            query: value.text,
          );
        },
        onSelected: (tag) => unawaited(_submitTag(tagText: tag.text)),
        optionsViewBuilder: (context, onSelected, options) {
          return _TagOptionsView(
            options: options.toList(),
            onSelected: onSelected,
          );
        },
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) {
              return Builder(
                builder: (fieldContext) => Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape):
                        _DismissTagSuggestionsIntent(),
                  },
                  child: Actions(
                    actions: {
                      _DismissTagSuggestionsIntent:
                          CallbackAction<_DismissTagSuggestionsIntent>(
                            onInvoke: (_) {
                              if (_dismissSuggestionsOrCancel()) {
                                Actions.invoke(
                                  fieldContext,
                                  const DismissIntent(),
                                );
                              }
                              return null;
                            },
                          ),
                    },
                    child: TextField(
                      controller: textController,
                      focusNode: focusNode,
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Add tag',
                                onPressed: () => unawaited(_submitTag()),
                                icon: const Icon(Icons.check),
                              ),
                      ),
                      onChanged: _tagTextChanged,
                      onSubmitted: (_) {
                        final suggestions = _currentTagSuggestions();
                        if (!_suggestionsDismissed && suggestions.isNotEmpty) {
                          onFieldSubmitted();
                        } else {
                          unawaited(_submitTag());
                        }
                      },
                    ),
                  ),
                ),
              );
            },
      ),
    );
  }

  void _startAdding() {
    setState(() {
      _adding = true;
      _suggestionsDismissed = false;
      _autocompleteRevision += 1;
      _errorText = null;
      _tagController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tagFocusNode.requestFocus();
        _refreshAutocomplete();
      }
    });
  }

  void _cancelAdding() {
    if (!_adding || _submitting) {
      return;
    }

    setState(() {
      _adding = false;
      _suggestionsDismissed = false;
      _errorText = null;
      _tagController.clear();
    });
  }

  Future<void> _submitTag({String? tagText}) async {
    if (_submitting) {
      return;
    }

    late final TaskTag draft;
    try {
      draft = TaskTag.fromInput(tagText ?? _tagController.text);
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
        _suggestionsDismissed = false;
        _tagController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _autocompleteRevision += 1;
        _errorText = error.toString();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _adding && !_submitting) {
          _tagFocusNode.requestFocus();
          _refreshAutocomplete();
        }
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

  List<TaskTag> _currentTagSuggestions() {
    return widget.controller.tagSuggestions(
      assignedTags: widget.row.tags,
      query: _tagController.text,
    );
  }

  void _tagTextChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  void _tagControllerChanged() {
    if (_suggestionsDismissed && !_refreshingAutocomplete) {
      setState(() => _suggestionsDismissed = false);
    }
  }

  void _refreshAutocomplete() {
    _refreshingAutocomplete = true;
    try {
      _tagController.refreshAutocomplete();
    } finally {
      _refreshingAutocomplete = false;
    }
  }

  bool _dismissSuggestionsOrCancel() {
    if (!_suggestionsDismissed && _currentTagSuggestions().isNotEmpty) {
      setState(() => _suggestionsDismissed = true);
      return true;
    }
    _cancelAdding();
    return false;
  }
}

class _DismissTagSuggestionsIntent extends Intent {
  const _DismissTagSuggestionsIntent();
}

class _TagOptionsView extends StatefulWidget {
  const _TagOptionsView({required this.options, required this.onSelected});

  final List<TaskTag> options;
  final AutocompleteOnSelected<TaskTag> onSelected;

  @override
  State<_TagOptionsView> createState() => _TagOptionsViewState();
}

class _TagOptionsViewState extends State<_TagOptionsView> {
  final ScrollController _scrollController = ScrollController();
  int? _lastHighlightedIndex;

  @override
  void didUpdateWidget(_TagOptionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.options, widget.options)) {
      _lastHighlightedIndex = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);
    final rowHeight = metrics.atLeast(40, 2.5);
    final highlightedIndex = AutocompleteHighlightedOption.of(context);
    _ensureHighlightedVisible(highlightedIndex, rowHeight);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(metrics.size(0.5)),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: rowHeight * 5,
          minWidth: metrics.maxWidth(12, min: 160),
        ),
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemExtent: rowHeight,
          itemCount: widget.options.length,
          itemBuilder: (context, index) {
            final option = widget.options[index];
            final highlighted = index == highlightedIndex;
            return InkWell(
              onTap: () => widget.onSelected(option),
              child: Container(
                alignment: Alignment.centerLeft,
                padding: metrics.insetsSymmetric(horizontal: 0.75),
                color: highlighted
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                child: Text(
                  option.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _ensureHighlightedVisible(int index, double rowHeight) {
    if (_lastHighlightedIndex == index) {
      return;
    }
    _lastHighlightedIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final itemTop = index * rowHeight;
      final itemBottom = itemTop + rowHeight;
      if (itemTop < position.pixels) {
        _scrollController.jumpTo(itemTop);
      } else if (itemBottom > position.pixels + position.viewportDimension) {
        _scrollController.jumpTo(itemBottom - position.viewportDimension);
      }
    });
  }
}

class _TagTextEditingController extends TextEditingController {
  void refreshAutocomplete() => notifyListeners();
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
