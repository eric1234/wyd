import 'dart:async';

import '../domain/domain.dart';
import 'diagnostic_logger.dart';
import 'platform_adapters.dart';
import 'tracker_service.dart';

enum LifecycleUiDisposition { showPrompt, hidePrompt, leaveUi, restorePrompt }

final class LifecycleUiDirective {
  const LifecycleUiDirective({
    required this.activeTask,
    required this.runtimeState,
    required this.disposition,
    this.terminal = false,
  });

  final ActiveTask? activeTask;
  final RuntimeState runtimeState;
  final LifecycleUiDisposition disposition;
  final bool terminal;
}

final class LifecycleCoordinator {
  LifecycleCoordinator({
    required TrackerService trackerService,
    DiagnosticLogger logger = const NoOpDiagnosticLogger(),
  }) : _trackerService = trackerService,
       _logger = logger;

  final TrackerService _trackerService;
  final DiagnosticLogger _logger;
  final StreamController<LifecycleUiDirective> _directives =
      StreamController.broadcast(sync: true);

  Future<void> _eventChain = Future.value();
  bool _promptPending = false;
  bool _shutdownCancellationEligible = false;
  bool _terminal = false;
  bool _disposed = false;
  TrackingBoundaryResult? _lastBoundary;

  Stream<LifecycleUiDirective> get directives => _directives.stream;
  bool get isTerminal => _terminal;

  Future<void> handle(LifecycleEventOccurrence occurrence) {
    if (_disposed || _terminal) {
      return Future.value();
    }
    if (occurrence.kind == LifecycleEventKind.termination) {
      _terminal = true;
    }

    final completion = Completer<void>();
    final operation = _eventChain.then((_) async {
      if (_disposed) {
        return;
      }
      await _handle(occurrence);
    });
    operation.then(
      (_) => completion.complete(),
      onError: (Object error, StackTrace stackTrace) {
        _logger.error('lifecycle event persistence failed', error, stackTrace);
        completion.completeError(error, stackTrace);
      },
    );
    _eventChain = operation.then<void>((_) {}, onError: (_) {});
    return completion.future;
  }

  Future<void> _handle(LifecycleEventOccurrence occurrence) async {
    if (occurrence.kind == LifecycleEventKind.shutdownCancelled) {
      if (_terminal) {
        return;
      }
      final result = _lastBoundary;
      if (result == null) {
        _shutdownCancellationEligible = false;
        return;
      }
      final restore = _shutdownCancellationEligible;
      _shutdownCancellationEligible = false;
      _promptPending = false;
      _publish(
        LifecycleUiDirective(
          activeTask: result.activeTask,
          runtimeState: result.runtimeState,
          disposition: restore
              ? LifecycleUiDisposition.restorePrompt
              : LifecycleUiDisposition.leaveUi,
        ),
      );
      return;
    }

    final kind = occurrence.kind;
    final cleanShutdown =
        kind == LifecycleEventKind.shutdown ||
        kind == LifecycleEventKind.termination;
    final source = switch (kind) {
      LifecycleEventKind.lock => ActivitySource.systemLock,
      LifecycleEventKind.sleep => ActivitySource.systemSleep,
      LifecycleEventKind.shutdown ||
      LifecycleEventKind.termination => ActivitySource.exit,
      LifecycleEventKind.shutdownCancelled => throw StateError(
        'Shutdown cancellation does not persist a boundary.',
      ),
    };
    final result = await _trackerService.applyBoundary(
      source: source,
      occurredAtUtc: occurrence.occurredAtUtc,
      cleanShutdown: cleanShutdown,
    );
    _lastBoundary = result;

    if (kind == LifecycleEventKind.termination) {
      _promptPending = false;
      _shutdownCancellationEligible = false;
      _publish(_directive(result, LifecycleUiDisposition.hidePrompt, true));
      return;
    }
    if (kind == LifecycleEventKind.shutdown) {
      _shutdownCancellationEligible =
          result.didStopActiveTask || _promptPending;
      _promptPending = false;
      _publish(_directive(result, LifecycleUiDisposition.hidePrompt));
      return;
    }

    _promptPending = _promptPending || result.didStopActiveTask;
    _publish(
      _directive(
        result,
        _promptPending
            ? LifecycleUiDisposition.showPrompt
            : LifecycleUiDisposition.leaveUi,
      ),
    );
  }

  LifecycleUiDirective _directive(
    TrackingBoundaryResult result,
    LifecycleUiDisposition disposition, [
    bool terminal = false,
  ]) {
    return LifecycleUiDirective(
      activeTask: result.activeTask,
      runtimeState: result.runtimeState,
      disposition: disposition,
      terminal: terminal,
    );
  }

  void _publish(LifecycleUiDirective directive) {
    if (!_disposed) {
      _directives.add(directive);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventChain;
    await _directives.close();
  }
}
