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
    final savedSnapshot = await _trackerService.updateSettings(
      normalizedSettings,
    );
    try {
      if (shouldUpdateStartup) {
        await _startupAtLoginAdapter.setEnabled(
          normalizedSettings.startAtLogin,
        );
      }
      return savedSnapshot;
    } catch (error) {
      await _rollbackPersistedSettings(current.settings);
      throw StateError(
        'Settings were saved, but start-at-login could not be updated: $error',
      );
    }
  }

  Future<void> reconcileStartAtLogin(AppStateSnapshot snapshot) async {
    if (!snapshot.capabilities.supportsStartAtLogin) {
      return;
    }

    final persisted = snapshot.settings.startAtLogin;
    final actual = await _startupAtLoginAdapter.isEnabled();
    if (actual != persisted) {
      await _startupAtLoginAdapter.setEnabled(persisted);
    }
  }

  Future<void> _rollbackPersistedSettings(AppSettings previousSettings) async {
    try {
      await _trackerService.updateSettings(previousSettings);
    } catch (_) {
      // Preserve the platform-side failure; the next startup reconciliation will
      // attempt to make the platform match persisted settings again.
    }
  }
}
