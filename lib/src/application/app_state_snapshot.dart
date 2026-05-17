import '../domain/domain.dart';

final class PlatformCapabilities {
  const PlatformCapabilities({
    this.supportsUserIdleDetection = false,
    this.supportsStartAtLogin = false,
    this.supportsPowerEvents = false,
    this.supportsTrayClickActions = false,
    this.supportsTrayRelativePositioning = false,
  });

  final bool supportsUserIdleDetection;
  final bool supportsStartAtLogin;
  final bool supportsPowerEvents;
  final bool supportsTrayClickActions;
  final bool supportsTrayRelativePositioning;

  @override
  bool operator ==(Object other) {
    return other is PlatformCapabilities &&
        supportsUserIdleDetection == other.supportsUserIdleDetection &&
        supportsStartAtLogin == other.supportsStartAtLogin &&
        supportsPowerEvents == other.supportsPowerEvents &&
        supportsTrayClickActions == other.supportsTrayClickActions &&
        supportsTrayRelativePositioning ==
            other.supportsTrayRelativePositioning;
  }

  @override
  int get hashCode {
    return Object.hash(
      supportsUserIdleDetection,
      supportsStartAtLogin,
      supportsPowerEvents,
      supportsTrayClickActions,
      supportsTrayRelativePositioning,
    );
  }
}

final class AppStateSnapshot {
  const AppStateSnapshot({
    required this.activeTask,
    required this.runtimeState,
    required this.settings,
    this.capabilities = const PlatformCapabilities(),
    this.recentSuggestions = const [],
    this.busy = false,
    this.errorMessage,
  });

  final ActiveTask? activeTask;
  final RuntimeState runtimeState;
  final AppSettings settings;
  final PlatformCapabilities capabilities;
  final List<AutocompleteSuggestion> recentSuggestions;
  final bool busy;
  final String? errorMessage;

  bool get isTracking => activeTask != null;
  bool get hasPendingPrompt => runtimeState.promptState.isPending;

  AppStateSnapshot copyWith({
    ActiveTask? activeTask,
    bool clearActiveTask = false,
    RuntimeState? runtimeState,
    AppSettings? settings,
    PlatformCapabilities? capabilities,
    List<AutocompleteSuggestion>? recentSuggestions,
    bool? busy,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AppStateSnapshot(
      activeTask: clearActiveTask ? null : activeTask ?? this.activeTask,
      runtimeState: runtimeState ?? this.runtimeState,
      settings: settings ?? this.settings,
      capabilities: capabilities ?? this.capabilities,
      recentSuggestions: recentSuggestions ?? this.recentSuggestions,
      busy: busy ?? this.busy,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}
