import '../domain/domain.dart';
import 'clock.dart';
import 'repositories.dart';

abstract interface class DailyReportLoader {
  DateTime todayLocalDate();

  Future<DailyReport> loadDailyReport(DateTime localDate);
}

final class ReportService implements DailyReportLoader {
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
  Future<DailyReport> loadDailyReport(DateTime localDate) {
    final selectedLocalDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    final dayStartUtc = selectedLocalDate.toUtc();
    final dayEndUtc = DateTime(
      selectedLocalDate.year,
      selectedLocalDate.month,
      selectedLocalDate.day + 1,
    ).toUtc();
    final nowUtc = _clock.nowUtc();
    final reportEndUtc = nowUtc.isBefore(dayEndUtc) ? nowUtc : dayEndUtc;

    return _transactions.run((transaction) async {
      final priorEvent = await transaction.activityLog.latestEventBefore(
        dayStartUtc,
      );
      final events = await transaction.activityLog.eventsBetween(
        fromUtc: dayStartUtc,
        throughUtc: reportEndUtc,
      );
      return ActivityTimeline([
        ?priorEvent,
        ...events,
      ]).buildDailyReport(localDate: selectedLocalDate, nowUtc: reportEndUtc);
    });
  }
}
