import '../domain/domain.dart';
import 'clock.dart';
import 'repositories.dart';

abstract interface class ActivityReportLoader {
  DateTime todayLocalDate();

  Future<ActivityReport> loadReport(ReportDateRange dateRange);
}

final class ReportService implements ActivityReportLoader {
  const ReportService({
    required TransactionRunner transactions,
    required Clock clock,
  }) : _transactions = transactions,
       _clock = clock;

  final TransactionRunner _transactions;
  final Clock _clock;

  @override
  DateTime todayLocalDate() {
    final nowLocal = _clock.nowUtc().toLocal();
    return DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  }

  @override
  Future<ActivityReport> loadReport(ReportDateRange dateRange) {
    final rangeStartUtc = dateRange.startLocalDateInclusive.toUtc();
    final rangeEndUtc = dateRange.endLocalDateExclusive.toUtc();
    final nowUtc = _clock.nowUtc();
    final reportEndUtc = nowUtc.isBefore(rangeEndUtc) ? nowUtc : rangeEndUtc;

    if (!reportEndUtc.isAfter(rangeStartUtc)) {
      return Future.value(
        ActivityReport(totalDuration: Duration.zero, rows: const []),
      );
    }

    return _transactions.run((transaction) async {
      final priorEvent = await transaction.activityLog.latestEventBefore(
        rangeStartUtc,
      );
      final events = await transaction.activityLog.eventsBetween(
        fromUtc: rangeStartUtc,
        throughUtc: reportEndUtc,
      );
      return ActivityTimeline([
        ?priorEvent,
        ...events,
      ]).buildReport(dateRange: dateRange, nowUtc: reportEndUtc);
    });
  }
}
