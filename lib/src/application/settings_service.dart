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
    try {
      if (shouldUpdateStartup) {
        await _startupAtLoginAdapter.setEnabled(
          normalizedSettings.startAtLogin,
        );
        startupUpdated = true;
      }
      return await _trackerService.updateSettings(normalizedSettings);
    } catch (error) {
      if (startupUpdated) {
        await _rollbackStartAtLogin(current.settings.startAtLogin);
      }
      throw StateError('Settings were not saved or applied: $error');
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

  Future<void> _rollbackStartAtLogin(bool previousValue) async {
    try {
      await _startupAtLoginAdapter.setEnabled(previousValue);
    } catch (_) {
      // Preserve the original failure. Startup reconciliation will make the
      // platform match the still-authoritative persisted setting later.
    }
  }
}
