import '../domain/domain.dart';
import 'app_state_snapshot.dart';
import 'platform_adapters.dart';
import 'tracker_service.dart';

abstract interface class SettingsClient {
  Future<AppStateSnapshot> loadSettingsSnapshot();

  Future<AppStateSnapshot> saveSettings(AppSettings settings);
}

final class SettingsService implements SettingsClient {
  const SettingsService({
    required TrackerService trackerService,
    required StartupAtLoginAdapter startupAtLoginAdapter,
  }) : _trackerService = trackerService,
       _startupAtLoginAdapter = startupAtLoginAdapter;

  final TrackerService _trackerService;
  final StartupAtLoginAdapter _startupAtLoginAdapter;

  @override
  Future<AppStateSnapshot> loadSettingsSnapshot() {
    return _trackerService.loadSnapshot();
  }

  @override
  Future<AppStateSnapshot> saveSettings(AppSettings settings) async {
    final current = await _trackerService.loadSnapshot();
    final capabilities = current.capabilities;
    final normalizedSettings = capabilities.supportsStartAtLogin
        ? settings
        : settings.copyWith(startAtLogin: false);

    if (capabilities.supportsStartAtLogin &&
        current.settings.startAtLogin != normalizedSettings.startAtLogin) {
      await _startupAtLoginAdapter.setEnabled(normalizedSettings.startAtLogin);
    }

    return _trackerService.updateSettings(normalizedSettings);
  }
}
