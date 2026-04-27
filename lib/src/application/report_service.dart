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
    return _transactions.run((transaction) async {
      final events = await transaction.activityLog.allEvents();
      return ReportDeriver.buildDailyReport(
        events: events,
        localDate: localDate,
        nowUtc: _clock.nowUtc(),
      );
    });
  }
}
