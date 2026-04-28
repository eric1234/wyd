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
    final issues = normalizedSettings.validate();
    if (issues.isNotEmpty) {
      throw AppSettingsValidationException(issues);
    }

    final shouldUpdateStartup =
        capabilities.supportsStartAtLogin &&
        current.settings.startAtLogin != normalizedSettings.startAtLogin;
    var startupUpdated = false;
    if (shouldUpdateStartup) {
      await _startupAtLoginAdapter.setEnabled(normalizedSettings.startAtLogin);
      startupUpdated = true;
    }

    try {
      return await _trackerService.updateSettings(normalizedSettings);
    } catch (_) {
      if (startupUpdated) {
        try {
          await _startupAtLoginAdapter.setEnabled(
            current.settings.startAtLogin,
          );
        } catch (_) {
          // Preserve the persistence failure; persisted settings remain authoritative.
        }
      }
      rethrow;
    }
  }
}
