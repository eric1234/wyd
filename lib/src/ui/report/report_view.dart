import 'package:flutter/material.dart';

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
    final selectedDate = _state.selectedDate;
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
              _DateHeader(
                title: selectedDate == null
                    ? 'Report'
                    : _formatDate(selectedDate),
                loading: _state.loading,
                canGoNext: _state.canGoNext,
                onPrevious: widget.controller.previousDay,
                onNext: widget.controller.nextDay,
              ),
              SizedBox(height: sectionGap),
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
                    message: 'Tracked time for this day will appear here.',
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
                        return ListTile(
                          title: Text(row.taskText),
                          trailing: Text(formatReportDuration(row.duration)),
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
              tooltip: 'Previous day',
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
              tooltip: 'Next day',
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
              'Tracked today',
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
