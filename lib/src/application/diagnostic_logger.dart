import 'dart:io';

abstract interface class DiagnosticLogger {
  void debug(String message);

  void error(String message, Object error, StackTrace stackTrace);
}

final class NoOpDiagnosticLogger implements DiagnosticLogger {
  const NoOpDiagnosticLogger();

  @override
  void debug(String message) {}

  @override
  void error(String message, Object error, StackTrace stackTrace) {}
}

final class EnvironmentDiagnosticLogger implements DiagnosticLogger {
  const EnvironmentDiagnosticLogger({
    this.environmentVariableName = 'WYD_DIAGNOSTICS',
    Map<String, String>? environment,
  }) : _environment = environment;

  final String environmentVariableName;
  final Map<String, String>? _environment;

  bool get isEnabled {
    final environment = _environment ?? Platform.environment;
    return environment[environmentVariableName]?.isNotEmpty ?? false;
  }

  @override
  void debug(String message) {
    if (!isEnabled) {
      return;
    }

    // ignore: avoid_print
    print('[wyd] $message');
  }

  @override
  void error(String message, Object error, StackTrace stackTrace) {
    if (!isEnabled) {
      return;
    }

    // ignore: avoid_print
    print('[wyd] $message: $error\n$stackTrace');
  }
}
