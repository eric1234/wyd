import 'app_state_snapshot.dart';
import 'platform_adapters.dart';

final class TrayMenuPresenter {
  const TrayMenuPresenter._();

  static List<TrayMenuEntry> build(AppStateSnapshot snapshot) {
    return [
      const TrayMenuEntry(
        action: TrayMenuAction.updateTask,
        label: 'Update Task',
      ),
      TrayMenuEntry(
        action: TrayMenuAction.stopTask,
        label: 'Stop Task',
        enabled: snapshot.activeTask != null,
      ),
      const TrayMenuEntry(action: TrayMenuAction.report, label: 'Report'),
      const TrayMenuEntry(action: TrayMenuAction.settings, label: 'Settings'),
      const TrayMenuEntry(action: TrayMenuAction.exit, label: 'Exit'),
    ];
  }

  static TrayIconStatus buildIconStatus(AppStateSnapshot snapshot) {
    return snapshot.isTracking ? TrayIconStatus.tracking : TrayIconStatus.idle;
  }
}
