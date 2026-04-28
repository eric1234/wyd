import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';

final class ReportState {
  const ReportState({
    this.selectedDate,
    this.today,
    this.report,
    this.loading = false,
    this.errorMessage,
    this.isOpen = false,
  });

  final DateTime? selectedDate;
  final DateTime? today;
  final DailyReport? report;
  final bool loading;
  final String? errorMessage;
  final bool isOpen;

  bool get canGoNext {
    final selected = selectedDate;
    final currentToday = today;
    if (selected == null || currentToday == null) {
      return false;
    }

    return selected.isBefore(currentToday);
  }

  ReportState copyWith({
    DateTime? selectedDate,
    DateTime? today,
    DailyReport? report,
    bool clearReport = false,
    bool? loading,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOpen,
  }) {
    return ReportState(
      selectedDate: selectedDate ?? this.selectedDate,
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

  final DailyReportLoader _service;
  ReportState _state = const ReportState();

  ReportState get state => _state;

  Future<void> open() async {
    if (_state.isOpen && _state.report != null) {
      return;
    }

    await loadDate(_service.todayLocalDate(), isOpen: true);
  }

  void refreshForShow() {
    final selected = _state.selectedDate ?? _service.todayLocalDate();
    unawaited(loadDate(selected, isOpen: true, clearReport: true));
  }

  void close() {
    _setState(_state.copyWith(isOpen: false));
  }

  Future<void> previousDay() async {
    final selected = _state.selectedDate ?? _service.todayLocalDate();
    await loadDate(DateTime(selected.year, selected.month, selected.day - 1));
  }

  Future<void> nextDay() async {
    if (!_state.canGoNext) {
      return;
    }

    final selected = _state.selectedDate!;
    await loadDate(DateTime(selected.year, selected.month, selected.day + 1));
  }

  Future<void> loadDate(
    DateTime localDate, {
    bool? isOpen,
    bool clearReport = false,
  }) async {
    final today = _service.todayLocalDate();
    final normalizedDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    if (normalizedDate.isAfter(today)) {
      return;
    }

    _setState(
      _state.copyWith(
        selectedDate: normalizedDate,
        today: today,
        loading: true,
        clearErrorMessage: true,
        clearReport: clearReport,
        isOpen: isOpen,
      ),
    );

    try {
      final report = await _service.loadDailyReport(normalizedDate);
      _setState(
        _state.copyWith(
          selectedDate: normalizedDate,
          today: today,
          report: report,
          loading: false,
          clearErrorMessage: true,
          isOpen: isOpen,
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          selectedDate: normalizedDate,
          today: today,
          loading: false,
          errorMessage: error.toString(),
          isOpen: isOpen,
        ),
      );
    }
  }

  void _setState(ReportState state) {
    _state = state;
    notifyListeners();
  }
}
