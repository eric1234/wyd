enum PromptStatus { none, visible, expired }

final class PromptState {
  const PromptState.none() : shownAtUtc = null, expired = false;

  PromptState.visible(DateTime shownAtUtc)
    : shownAtUtc = shownAtUtc.toUtc(),
      expired = false;

  PromptState.expired(DateTime shownAtUtc)
    : shownAtUtc = shownAtUtc.toUtc(),
      expired = true;

  final DateTime? shownAtUtc;
  final bool expired;

  PromptStatus get status {
    if (shownAtUtc == null) {
      return PromptStatus.none;
    }

    return expired ? PromptStatus.expired : PromptStatus.visible;
  }

  bool get isPending => shownAtUtc != null;
}

final class RuntimeState {
  RuntimeState({
    DateTime? lastConfirmationAtUtc,
    this.promptState = const PromptState.none(),
    this.cleanShutdown = true,
  }) : lastConfirmationAtUtc = lastConfirmationAtUtc?.toUtc();

  final DateTime? lastConfirmationAtUtc;
  final PromptState promptState;
  final bool cleanShutdown;

  RuntimeState copyWith({
    DateTime? lastConfirmationAtUtc,
    bool clearLastConfirmationAtUtc = false,
    PromptState? promptState,
    bool? cleanShutdown,
  }) {
    return RuntimeState(
      lastConfirmationAtUtc: clearLastConfirmationAtUtc
          ? null
          : (lastConfirmationAtUtc ?? this.lastConfirmationAtUtc)?.toUtc(),
      promptState: promptState ?? this.promptState,
      cleanShutdown: cleanShutdown ?? this.cleanShutdown,
    );
  }
}
