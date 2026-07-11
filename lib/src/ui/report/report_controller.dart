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
  });

  final ReportSelection? selection;
  final DateTime? today;
  final ActivityReport? report;
  final bool loading;
  final String? errorMessage;
  final bool isOpen;

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
    );
  }
}

final class ReportController extends ChangeNotifier {
  ReportController(this._service);

  final ActivityReportLoader _service;
  ReportState _state = const ReportState();
  int _loadRequest = 0;

  ReportState get state => _state;

  Future<void> open() async {
    if (_state.isOpen && _state.report != null) {
      return;
    }

    await loadSelection(
      ReportSelection(
        preset: ReportRangePreset.day,
        anchorDate: _service.todayLocalDate(),
      ),
      isOpen: true,
    );
  }

  void refreshForShow() {
    final selection = _state.isOpen
        ? _state.selection ?? _todaySelection()
        : _todaySelection();
    unawaited(loadSelection(selection, isOpen: true, clearReport: true));
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

  ReportSelection _todaySelection() => ReportSelection(
    preset: ReportRangePreset.day,
    anchorDate: _service.todayLocalDate(),
  );

  void _setState(ReportState state) {
    _state = state;
    notifyListeners();
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
