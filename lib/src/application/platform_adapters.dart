enum TrayMenuAction { updateTask, stopTask, report, settings, exit }

final class TrayMenuEntry {
  const TrayMenuEntry({
    required this.action,
    required this.label,
    this.enabled = true,
  });

  final TrayMenuAction action;
  final String label;
  final bool enabled;
}

abstract interface class TrayAdapter {
  Stream<TrayMenuAction> get menuActions;

  Stream<void> get primaryClicks;

  Future<void> initialize(List<TrayMenuEntry> entries);

  Future<void> updateMenu(List<TrayMenuEntry> entries);

  Future<void> dispose();
}

enum WindowRole { quickEntry, report, settings }

final class WindowRoleConfiguration {
  const WindowRoleConfiguration({
    required this.role,
    required this.title,
    required this.width,
    required this.height,
    this.resizable = true,
    this.alwaysOnTop = false,
  });

  static const quickEntryWidth = 420.0;
  static const quickEntryHeight = 304.0;

  factory WindowRoleConfiguration.quickEntry() {
    return const WindowRoleConfiguration(
      role: WindowRole.quickEntry,
      title: 'Update Task',
      width: quickEntryWidth,
      height: quickEntryHeight,
      resizable: false,
      alwaysOnTop: true,
    );
  }

  factory WindowRoleConfiguration.startupError() {
    return const WindowRoleConfiguration(
      role: WindowRole.quickEntry,
      title: 'wyd startup error',
      width: 560,
      height: 360,
      resizable: false,
      alwaysOnTop: true,
    );
  }

  factory WindowRoleConfiguration.runtimeError() {
    return const WindowRoleConfiguration(
      role: WindowRole.quickEntry,
      title: 'wyd error',
      width: 560,
      height: 320,
      resizable: false,
      alwaysOnTop: true,
    );
  }

  factory WindowRoleConfiguration.forRole(WindowRole role) {
    return switch (role) {
      WindowRole.quickEntry => WindowRoleConfiguration.quickEntry(),
      WindowRole.report => const WindowRoleConfiguration(
        role: WindowRole.report,
        title: 'Report',
        width: 720,
        height: 560,
      ),
      WindowRole.settings => const WindowRoleConfiguration(
        role: WindowRole.settings,
        title: 'Settings',
        width: 520,
        height: 460,
      ),
    };
  }

  final WindowRole role;
  final String title;
  final double width;
  final double height;
  final bool resizable;
  final bool alwaysOnTop;
}

final class WindowHandle {
  const WindowHandle(this.id);

  final String id;
}

abstract interface class WindowAdapter {
  Stream<WindowHandle> get closeRequests;

  Future<WindowHandle> open(WindowRoleConfiguration configuration);

  Future<WindowHandle> preload(WindowRoleConfiguration configuration);

  Future<bool> isOpen(WindowHandle handle);

  Future<void> focus(WindowHandle handle);

  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  );

  Future<void> close(WindowHandle handle);
}

abstract interface class SingleInstanceAdapter {
  Future<void> initialize(Future<void> Function() onSecondInstanceActivated);
}

abstract interface class StartupAtLoginAdapter {
  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);
}

final class UnsupportedStartupAtLoginAdapter implements StartupAtLoginAdapter {
  const UnsupportedStartupAtLoginAdapter();

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      throw UnsupportedError('Start at login is unsupported on this platform.');
    }
  }
}

abstract interface class PowerEventAdapter {
  Stream<PowerEvent> get events;
}

enum PowerEvent { lock, sleep }

final class UnsupportedPowerEventAdapter implements PowerEventAdapter {
  const UnsupportedPowerEventAdapter();

  @override
  Stream<PowerEvent> get events => const Stream.empty();
}

abstract interface class TypingActivityDetector {
  Future<DateTime?> lastTypingActivityUtc();
}

final class UnsupportedTypingActivityDetector
    implements TypingActivityDetector {
  const UnsupportedTypingActivityDetector();

  @override
  Future<DateTime?> lastTypingActivityUtc() async => null;
}
