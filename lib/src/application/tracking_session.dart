import '../domain/domain.dart';

final class TrackingSession {
  const TrackingSession({required this.timeline, required this.runtimeState});

  final ActivityTimeline timeline;
  final RuntimeState runtimeState;

  TrackingTransition submitTask({
    required String taskText,
    required DateTime nowUtc,
  }) {
    final result = timeline.submitTask(
      taskText: taskText,
      occurredAtUtc: nowUtc,
      createdAtUtc: nowUtc,
    );

    return TrackingTransition(
      eventToAppend: result.event,
      runtimeState: runtimeState.copyWith(
        lastConfirmationAtUtc: nowUtc,
        promptState: const PromptState.none(),
        cleanShutdown: false,
      ),
      saveRuntimeState: true,
      diagnosticAction: result.diagnosticName,
    );
  }

  TrackingTransition stopTask({
    required DateTime nowUtc,
    required ActivitySource source,
    DateTime? createdAtUtc,
  }) {
    final result = timeline.stopTask(
      occurredAtUtc: nowUtc,
      source: source,
      createdAtUtc: createdAtUtc ?? nowUtc,
    );
    final event = result.event;
    if (event == null) {
      return TrackingTransition.noChange(runtimeState);
    }

    return TrackingTransition(
      eventToAppend: event,
      runtimeState: runtimeState.copyWith(
        promptState: const PromptState.none(),
        cleanShutdown: false,
      ),
      saveRuntimeState: true,
    );
  }

  TrackingTransition exitRequested({
    required DateTime nowUtc,
    DateTime? occurredAtUtc,
  }) {
    final activeTask = timeline.activeTask;
    final shouldStopActiveTask =
        activeTask != null &&
        runtimeState.promptState.status != PromptStatus.expired;
    final stopOccurredAtUtc = occurredAtUtc?.toUtc() ?? nowUtc;

    return TrackingTransition(
      eventToAppend: shouldStopActiveTask
          ? ActivityLogEvent.stopTask(
              occurredAtUtc: stopOccurredAtUtc,
              source: ActivitySource.exit,
              createdAtUtc: nowUtc,
            )
          : null,
      runtimeState: runtimeState.copyWith(
        promptState: const PromptState.none(),
        cleanShutdown: true,
      ),
      saveRuntimeState: true,
    );
  }

  TrackingTransition nagPromptShown({required DateTime nowUtc}) {
    if (timeline.activeTask == null || runtimeState.promptState.isPending) {
      return TrackingTransition.noChange(runtimeState);
    }

    return TrackingTransition(
      runtimeState: runtimeState.copyWith(
        promptState: PromptState.visible(nowUtc),
        cleanShutdown: false,
      ),
      saveRuntimeState: true,
    );
  }

  TrackingTransition nagPromptTimedOut({required DateTime nowUtc}) {
    final shownAtUtc = runtimeState.promptState.shownAtUtc;
    if (timeline.activeTask == null ||
        shownAtUtc == null ||
        runtimeState.promptState.status == PromptStatus.expired) {
      return TrackingTransition.noChange(runtimeState);
    }

    return TrackingTransition(
      eventToAppend: ActivityLogEvent.stopTask(
        occurredAtUtc: shownAtUtc,
        source: ActivitySource.nagTimeout,
        createdAtUtc: nowUtc,
      ),
      runtimeState: runtimeState.copyWith(
        promptState: PromptState.expired(shownAtUtc),
        cleanShutdown: false,
      ),
      saveRuntimeState: true,
    );
  }

  TrackingTransition recoverOnStartup({required DateTime nowUtc}) {
    if (runtimeState.cleanShutdown) {
      return TrackingTransition(
        runtimeState: runtimeState.copyWith(cleanShutdown: false),
        saveRuntimeState: true,
      );
    }

    final activeTask = timeline.activeTask;
    final recoveryTimestamp = activeTask == null
        ? null
        : runtimeState.promptState.shownAtUtc ??
              runtimeState.lastConfirmationAtUtc ??
              activeTask.startedAtUtc;

    return TrackingTransition(
      eventToAppend: recoveryTimestamp == null
          ? null
          : ActivityLogEvent.stopTask(
              occurredAtUtc: recoveryTimestamp,
              source: ActivitySource.recovery,
              createdAtUtc: nowUtc,
            ),
      runtimeState: runtimeState.copyWith(
        promptState: const PromptState.none(),
        cleanShutdown: false,
      ),
      saveRuntimeState: true,
    );
  }
}

final class TrackingTransition {
  const TrackingTransition({
    this.eventToAppend,
    required this.runtimeState,
    required this.saveRuntimeState,
    this.diagnosticAction,
  });

  const TrackingTransition.noChange(RuntimeState runtimeState)
    : this(runtimeState: runtimeState, saveRuntimeState: false);

  final ActivityLogEvent? eventToAppend;
  final RuntimeState runtimeState;
  final bool saveRuntimeState;
  final String? diagnosticAction;
}
