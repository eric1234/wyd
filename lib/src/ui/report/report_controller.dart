import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';

enum ReportRangePreset { day, week, month, quarter, year }

final class ReportSelection {
  ReportSelection({required this.preset, required DateTime anchorDate})
    : anchorDate = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);

  final ReportRangePreset preset;
  final DateTime anchorDate;

  ReportDateRange get dateRange =>
      _dateRange(preset, _periodStart(preset, anchorDate));
}

final class ReportState {
  const ReportState({
    this.selection,
    this.today,
    this.report,
    this.loading = false,
    this.errorMessage,
    this.isOpen = false,
    this.availableTags = const [],
    this.visualizationPreferences,
    this.breakdown,
    this.preferenceErrorMessage,
  });

  final ReportSelection? selection;
  final DateTime? today;
  final ActivityReport? report;
  final bool loading;
  final String? errorMessage;
  final bool isOpen;
  final List<TaskTag> availableTags;
  final ReportVisualizationPreferences? visualizationPreferences;
  final ReportBreakdown? breakdown;
  final String? preferenceErrorMessage;

  ReportDateRange? get dateRange => selection?.dateRange;

  bool get canGoNext {
    final currentSelection = selection;
    final currentToday = today;
    if (currentSelection == null || currentToday == null) {
      return false;
    }

    final next = _shiftSelection(currentSelection, 1);
    return !next.anchorDate.isAfter(currentToday);
  }

  ReportState copyWith({
    ReportSelection? selection,
    DateTime? today,
    ActivityReport? report,
    bool clearReport = false,
    bool? loading,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOpen,
    List<TaskTag>? availableTags,
    ReportVisualizationPreferences? visualizationPreferences,
    ReportBreakdown? breakdown,
    String? preferenceErrorMessage,
    bool clearPreferenceErrorMessage = false,
  }) {
    return ReportState(
      selection: selection ?? this.selection,
      today: today ?? this.today,
      report: clearReport ? null : report ?? this.report,
      loading: loading ?? this.loading,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      isOpen: isOpen ?? this.isOpen,
      availableTags: availableTags ?? this.availableTags,
      visualizationPreferences:
          visualizationPreferences ?? this.visualizationPreferences,
      breakdown: breakdown ?? this.breakdown,
      preferenceErrorMessage: clearPreferenceErrorMessage
          ? null
          : preferenceErrorMessage ?? this.preferenceErrorMessage,
    );
  }
}

final class ReportController extends ChangeNotifier {
  ReportController(this._service);

  final ActivityReportLoader _service;
  ReportState _state = const ReportState();
  int _loadRequest = 0;
  int _preferenceSaveRequest = 0;
  int _persistedPreferenceRequest = 0;
  ReportVisualizationPreferences _persistedVisualizationPreferences =
      ReportVisualizationPreferences.defaults;

  ReportState get state => _state;

  Future<void> open() async {
    if (_state.isOpen && _state.report != null) {
      return;
    }

    final reportLoad = loadSelection(
      ReportSelection(
        preset: ReportRangePreset.day,
        anchorDate: _service.todayLocalDate(),
      ),
      isOpen: true,
    );
    final visualizationLoad = _loadVisualizationData();
    await Future.wait([reportLoad, visualizationLoad]);
  }

  Future<void> refreshForShow() async {
    final selection = _state.isOpen
        ? _state.selection ?? _todaySelection()
        : _todaySelection();
    final reportLoad = loadSelection(
      selection,
      isOpen: true,
      clearReport: true,
    );
    final visualizationLoad = _loadVisualizationData();
    await Future.wait([reportLoad, visualizationLoad]);
  }

  void close() {
    _loadRequest += 1;
    _setState(_state.copyWith(isOpen: false, loading: false));
  }

  Future<void> selectPreset(ReportRangePreset preset) async {
    final anchor = _state.selection?.anchorDate ?? _service.todayLocalDate();
    await loadSelection(ReportSelection(preset: preset, anchorDate: anchor));
  }

  Future<void> previousWindow() async {
    final selection = _state.selection ?? _todaySelection();
    await loadSelection(_shiftSelection(selection, -1));
  }

  Future<void> nextWindow() async {
    if (!_state.canGoNext) {
      return;
    }

    await loadSelection(_shiftSelection(_state.selection!, 1));
  }

  Future<void> loadSelection(
    ReportSelection selection, {
    bool? isOpen,
    bool clearReport = false,
  }) async {
    final today = _service.todayLocalDate();
    if (selection.anchorDate.isAfter(today)) {
      return;
    }
    final request = ++_loadRequest;

    _setState(
      _state.copyWith(
        selection: selection,
        today: today,
        loading: true,
        clearErrorMessage: true,
        clearReport: clearReport,
        isOpen: isOpen,
      ),
    );

    try {
      final report = await _service.loadReport(selection.dateRange);
      if (request != _loadRequest) {
        return;
      }
      _setState(
        _state.copyWith(
          selection: selection,
          today: today,
          report: report,
          breakdown: buildReportBreakdown(
            report,
            _state.visualizationPreferences ??
                ReportVisualizationPreferences.defaults,
          ),
          loading: false,
          clearErrorMessage: true,
          isOpen: isOpen,
        ),
      );
    } catch (error) {
      if (request != _loadRequest) {
        return;
      }
      _setState(
        _state.copyWith(
          selection: selection,
          today: today,
          loading: false,
          errorMessage: error.toString(),
          isOpen: isOpen,
        ),
      );
    }
  }

  Future<TaskTag> addTag({
    required String taskTextNormalized,
    required String tagText,
  }) async {
    final tag = await _service.addTaskTag(
      taskTextNormalized: taskTextNormalized,
      tagText: tagText,
    );
    _updateTagsForTask(taskTextNormalized, (tags) {
      return _sortTags([
        for (final existing in tags)
          if (existing.normalized != tag.normalized) existing,
        tag,
      ]);
    });
    await _loadVisualizationData();
    return tag;
  }

  Future<void> removeTag({
    required String taskTextNormalized,
    required TaskTag tag,
  }) async {
    await _service.removeTaskTag(
      taskTextNormalized: taskTextNormalized,
      tagTextNormalized: tag.normalized,
    );
    _updateTagsForTask(taskTextNormalized, (tags) {
      return [
        for (final existing in tags)
          if (existing.normalized != tag.normalized) existing,
      ];
    });
    await _loadVisualizationData();
  }

  Future<void> setGroupingMode(ReportGroupingMode mode) async {
    final current =
        _state.visualizationPreferences ??
        ReportVisualizationPreferences.defaults;
    final levels = mode == ReportGroupingMode.tags && current.tagLevels.isEmpty
        ? [ReportTagLevel(const [])]
        : current.tagLevels;
    await _savePreferences(current.copyWith(mode: mode, tagLevels: levels));
  }

  Future<void> setTagLevel(int index, Iterable<String> tags) async {
    final current =
        _state.visualizationPreferences ??
        ReportVisualizationPreferences.defaults;
    final levels = current.tagLevels.toList();
    while (levels.length <= index) {
      levels.add(ReportTagLevel(const []));
    }
    levels[index] = ReportTagLevel(tags);
    await _savePreferences(current.copyWith(tagLevels: levels));
  }

  Future<void> addTagLevel() async {
    final current =
        _state.visualizationPreferences ??
        ReportVisualizationPreferences.defaults;
    if (current.tagLevels.length >=
        ReportVisualizationPreferences.maxTagLevels) {
      return;
    }
    await _savePreferences(
      current.copyWith(
        tagLevels: [...current.tagLevels, ReportTagLevel(const [])],
      ),
    );
  }

  Future<void> removeTagLevel(int index) async {
    final current =
        _state.visualizationPreferences ??
        ReportVisualizationPreferences.defaults;
    final levels = current.tagLevels.toList();
    if (index < 0 || index >= levels.length) {
      return;
    }
    levels.removeAt(index);
    await _savePreferences(current.copyWith(tagLevels: levels));
  }

  void clearPreferenceError() {
    _setState(_state.copyWith(clearPreferenceErrorMessage: true));
  }

  ReportSelection _todaySelection() => ReportSelection(
    preset: ReportRangePreset.day,
    anchorDate: _service.todayLocalDate(),
  );

  void _setState(ReportState state) {
    _state = state;
    notifyListeners();
  }

  void _updateTagsForTask(
    String taskTextNormalized,
    List<TaskTag> Function(List<TaskTag> tags) update,
  ) {
    final report = _state.report;
    if (report == null) {
      return;
    }
    final updatedReport = ActivityReport(
      totalDuration: report.totalDuration,
      rows: [
        for (final row in report.rows)
          if (row.taskTextNormalized == taskTextNormalized)
            ReportRow(
              taskText: row.taskText,
              taskTextNormalized: row.taskTextNormalized,
              duration: row.duration,
              tags: update(row.tags),
            )
          else
            row,
      ],
    );

    _setState(
      _state.copyWith(
        report: updatedReport,
        breakdown: buildReportBreakdown(
          updatedReport,
          _state.visualizationPreferences ??
              ReportVisualizationPreferences.defaults,
        ),
      ),
    );
  }

  Future<void> _loadVisualizationData() async {
    final preferenceRequest = _preferenceSaveRequest;
    final data = await _service.loadVisualizationData();
    final report = _state.report;
    final preferences = preferenceRequest == _preferenceSaveRequest
        ? data.preferences
        : _state.visualizationPreferences ?? data.preferences;
    if (preferenceRequest == _preferenceSaveRequest) {
      _persistedVisualizationPreferences = data.preferences;
      _persistedPreferenceRequest = preferenceRequest;
    }
    _setState(
      _state.copyWith(
        availableTags: data.availableTags,
        visualizationPreferences: preferences,
        breakdown: report == null
            ? _state.breakdown
            : buildReportBreakdown(report, preferences),
      ),
    );
  }

  Future<void> _savePreferences(
    ReportVisualizationPreferences preferences,
  ) async {
    final request = ++_preferenceSaveRequest;
    final report = _state.report;
    _setState(
      _state.copyWith(
        visualizationPreferences: preferences,
        breakdown: report == null
            ? _state.breakdown
            : buildReportBreakdown(report, preferences),
        clearPreferenceErrorMessage: true,
      ),
    );
    try {
      await _service.saveVisualizationPreferences(preferences);
      if (request >= _persistedPreferenceRequest) {
        _persistedVisualizationPreferences = preferences;
        _persistedPreferenceRequest = request;
      }
    } catch (error) {
      if (request != _preferenceSaveRequest ||
          _state.visualizationPreferences != preferences) {
        return;
      }
      final persisted = _persistedVisualizationPreferences;
      _setState(
        _state.copyWith(
          visualizationPreferences: persisted,
          breakdown: report == null
              ? _state.breakdown
              : buildReportBreakdown(report, persisted),
          preferenceErrorMessage: 'Unable to save report grouping: $error',
        ),
      );
    }
  }

  List<TaskTag> _sortTags(List<TaskTag> tags) {
    return tags.toList()
      ..sort((left, right) => left.normalized.compareTo(right.normalized));
  }
}

ReportSelection _shiftSelection(ReportSelection selection, int amount) {
  final anchor = _periodStart(selection.preset, selection.anchorDate);
  final shifted = switch (selection.preset) {
    ReportRangePreset.day => DateTime(
      anchor.year,
      anchor.month,
      anchor.day + amount,
    ),
    ReportRangePreset.week => DateTime(
      anchor.year,
      anchor.month,
      anchor.day + (7 * amount),
    ),
    ReportRangePreset.month => DateTime(anchor.year, anchor.month + amount),
    ReportRangePreset.quarter => DateTime(
      anchor.year,
      anchor.month + (3 * amount),
    ),
    ReportRangePreset.year => DateTime(anchor.year + amount),
  };
  return ReportSelection(preset: selection.preset, anchorDate: shifted);
}

DateTime _periodStart(ReportRangePreset preset, DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return switch (preset) {
    ReportRangePreset.day => localDate,
    ReportRangePreset.week => DateTime(
      localDate.year,
      localDate.month,
      localDate.day - (localDate.weekday - DateTime.monday),
    ),
    ReportRangePreset.month => DateTime(localDate.year, localDate.month),
    ReportRangePreset.quarter => DateTime(
      localDate.year,
      ((localDate.month - 1) ~/ 3) * 3 + 1,
    ),
    ReportRangePreset.year => DateTime(localDate.year),
  };
}

ReportDateRange _dateRange(ReportRangePreset preset, DateTime periodStart) {
  final end = switch (preset) {
    ReportRangePreset.day => DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day + 1,
    ),
    ReportRangePreset.week => DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day + 7,
    ),
    ReportRangePreset.month => DateTime(
      periodStart.year,
      periodStart.month + 1,
    ),
    ReportRangePreset.quarter => DateTime(
      periodStart.year,
      periodStart.month + 3,
    ),
    ReportRangePreset.year => DateTime(periodStart.year + 1),
  };
  return ReportDateRange(
    startLocalDateInclusive: periodStart,
    endLocalDateExclusive: end,
  );
}
