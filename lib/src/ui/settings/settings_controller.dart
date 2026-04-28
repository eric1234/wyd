import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';

final class SettingsState {
  const SettingsState({
    this.isOpen = false,
    this.loading = false,
    this.saving = false,
    this.dirty = false,
    this.reminderIntervalMinutes = '',
    this.autocompleteLookbackDays = '',
    this.responseTimeoutMinutes = '',
    this.typingDeferralSeconds = '',
    this.startAtLogin = false,
    this.capabilities = const PlatformCapabilities(),
    this.validationIssues = const [],
    this.errorMessage,
    this.saved = false,
  });

  final bool isOpen;
  final bool loading;
  final bool saving;
  final bool dirty;
  final String reminderIntervalMinutes;
  final String autocompleteLookbackDays;
  final String responseTimeoutMinutes;
  final String typingDeferralSeconds;
  final bool startAtLogin;
  final PlatformCapabilities capabilities;
  final List<SettingsValidationIssue> validationIssues;
  final String? errorMessage;
  final bool saved;

  String? messageFor(SettingsField field) {
    for (final issue in validationIssues) {
      if (issue.field == field) {
        return issue.message;
      }
    }

    return null;
  }

  SettingsState copyWith({
    bool? isOpen,
    bool? loading,
    bool? saving,
    bool? dirty,
    String? reminderIntervalMinutes,
    String? autocompleteLookbackDays,
    String? responseTimeoutMinutes,
    String? typingDeferralSeconds,
    bool? startAtLogin,
    PlatformCapabilities? capabilities,
    List<SettingsValidationIssue>? validationIssues,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? saved,
  }) {
    return SettingsState(
      isOpen: isOpen ?? this.isOpen,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      dirty: dirty ?? this.dirty,
      reminderIntervalMinutes:
          reminderIntervalMinutes ?? this.reminderIntervalMinutes,
      autocompleteLookbackDays:
          autocompleteLookbackDays ?? this.autocompleteLookbackDays,
      responseTimeoutMinutes:
          responseTimeoutMinutes ?? this.responseTimeoutMinutes,
      typingDeferralSeconds:
          typingDeferralSeconds ?? this.typingDeferralSeconds,
      startAtLogin: startAtLogin ?? this.startAtLogin,
      capabilities: capabilities ?? this.capabilities,
      validationIssues: validationIssues ?? this.validationIssues,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      saved: saved ?? this.saved,
    );
  }
}

final class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsClient client,
    required Future<void> Function(AppStateSnapshot snapshot) onSaved,
  }) : _client = client,
       _onSaved = onSaved;

  final SettingsClient _client;
  final Future<void> Function(AppStateSnapshot snapshot) _onSaved;

  SettingsState _state = const SettingsState();
  AppSettings? _lastSavedSettings;
  _SettingsSaveRequest? _activeSave;
  _SettingsSaveRequest? _queuedSave;
  Future<void>? _saveQueueFuture;
  int _draftRevision = 0;

  SettingsState get state => _state;

  Future<void> open({bool forceReload = false}) async {
    if (_state.isOpen && !_state.loading && !forceReload) {
      return;
    }

    _setState(
      _state.copyWith(
        isOpen: true,
        loading: true,
        dirty: false,
        saved: false,
        validationIssues: const [],
        clearErrorMessage: true,
      ),
    );

    try {
      final snapshot = await _client.loadSettingsSnapshot();
      _lastSavedSettings = _SettingsDraft.fromSnapshot(snapshot).toSettings();
      _draftRevision += 1;
      _setState(_fromSnapshot(snapshot).copyWith(isOpen: true));
    } catch (error) {
      _setState(
        _state.copyWith(
          loading: false,
          errorMessage: error.toString(),
          saved: false,
        ),
      );
    }
  }

  void refreshForShow() {
    if (_state.dirty || _saveQueueFuture != null) {
      _setState(_state.copyWith(isOpen: true));
      return;
    }

    unawaited(open(forceReload: true));
  }

  Future<void> close() async {
    if (_lastSavedSettings != null) {
      await commitChanges();
    }
    _setState(_state.copyWith(isOpen: false));
  }

  void updateReminderInterval(String value) {
    if (_state.reminderIntervalMinutes == value) {
      return;
    }

    _updateDraft(_state.copyWith(reminderIntervalMinutes: value));
  }

  void updateAutocompleteLookback(String value) {
    if (_state.autocompleteLookbackDays == value) {
      return;
    }

    _updateDraft(_state.copyWith(autocompleteLookbackDays: value));
  }

  void updateResponseTimeout(String value) {
    if (_state.responseTimeoutMinutes == value) {
      return;
    }

    _updateDraft(_state.copyWith(responseTimeoutMinutes: value));
  }

  void updateTypingDeferral(String value) {
    if (_state.typingDeferralSeconds == value) {
      return;
    }

    _updateDraft(_state.copyWith(typingDeferralSeconds: value));
  }

  Future<void> updateStartAtLogin(bool value) async {
    if (!_state.capabilities.supportsStartAtLogin) {
      return;
    }
    if (_state.startAtLogin == value) {
      return;
    }

    _updateDraft(_state.copyWith(startAtLogin: value));
    await commitChanges();
  }

  Future<void> save() {
    return commitChanges();
  }

  Future<void> commitChanges() async {
    if (_state.loading) {
      return;
    }

    final parseResult = _parseSettings();
    if (parseResult.issues.isNotEmpty) {
      _queuedSave = null;
      _setState(
        _state.copyWith(
          validationIssues: parseResult.issues,
          dirty: true,
          saved: false,
          clearErrorMessage: true,
        ),
      );
      return;
    }

    final settings = parseResult.settings!;
    final issues = settings.validate();
    if (issues.isNotEmpty) {
      _queuedSave = null;
      _setState(
        _state.copyWith(
          validationIssues: issues,
          dirty: true,
          saved: false,
          clearErrorMessage: true,
        ),
      );
      return;
    }

    if (_saveQueueFuture == null && settings == _lastSavedSettings) {
      _queuedSave = null;
      _setState(
        _state.copyWith(
          validationIssues: const [],
          dirty: false,
          saved: false,
          clearErrorMessage: true,
        ),
      );
      return;
    }

    if (_saveQueueFuture != null &&
        (settings == _activeSave?.settings ||
            settings == _queuedSave?.settings)) {
      await _saveQueueFuture;
      return;
    }

    await _enqueueSave(_SettingsSaveRequest(settings, _draftRevision));
  }

  void _updateDraft(SettingsState state) {
    _draftRevision += 1;
    _setState(
      state.copyWith(
        validationIssues: const [],
        dirty: true,
        saved: false,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> _enqueueSave(_SettingsSaveRequest request) {
    _queuedSave = request;
    _saveQueueFuture ??= _drainSaveQueue().whenComplete(() {
      _saveQueueFuture = null;
    });

    return _saveQueueFuture!;
  }

  Future<void> _drainSaveQueue() async {
    while (_queuedSave != null) {
      final request = _queuedSave!;
      _queuedSave = null;
      _activeSave = request;

      _setState(
        _state.copyWith(
          saving: true,
          validationIssues: const [],
          saved: false,
          clearErrorMessage: true,
        ),
      );

      final saved = await _saveRequest(request);
      _activeSave = null;
      if (!saved && _queuedSave == null) {
        break;
      }
    }

    if (_state.saving) {
      _setState(_state.copyWith(saving: false, dirty: _draftIsDirty()));
    }
  }

  Future<bool> _saveRequest(_SettingsSaveRequest request) async {
    _setState(
      _state.copyWith(
        saving: true,
        validationIssues: const [],
        saved: false,
        clearErrorMessage: true,
      ),
    );

    try {
      final snapshot = await _client.saveSettings(request.settings);
      _lastSavedSettings = _SettingsDraft.fromSnapshot(snapshot).toSettings();
      final saveMatchesCurrentDraft = request.draftRevision == _draftRevision;
      if (saveMatchesCurrentDraft) {
        _setState(
          _fromSnapshot(snapshot).copyWith(
            isOpen: _state.isOpen,
            saving: true,
            dirty: false,
            saved: true,
          ),
        );
      } else {
        _setState(
          _state.copyWith(
            capabilities: snapshot.capabilities,
            saving: true,
            dirty: _draftIsDirty(),
            saved: false,
            clearErrorMessage: true,
          ),
        );
      }
      await _onSaved(snapshot);
      return true;
    } on AppSettingsValidationException catch (error) {
      if (request.draftRevision == _draftRevision) {
        _setState(
          _state.copyWith(
            saving: true,
            validationIssues: error.issues,
            dirty: _draftIsDirty(),
            saved: false,
          ),
        );
      }
      return false;
    } catch (error) {
      if (request.draftRevision == _draftRevision) {
        _setState(
          _state.copyWith(
            saving: true,
            errorMessage: error.toString(),
            dirty: _draftIsDirty(),
            saved: false,
          ),
        );
      }
      return false;
    }
  }

  SettingsState _fromSnapshot(AppStateSnapshot snapshot) {
    return _SettingsDraft.fromSnapshot(snapshot).toState(isOpen: _state.isOpen);
  }

  _SettingsParseResult _parseSettings() {
    return _SettingsDraft.fromState(_state).parse();
  }

  bool _draftIsDirty() {
    return _SettingsDraft.fromState(
      _state,
    ).isDirtyComparedWith(_lastSavedSettings);
  }

  void _setState(SettingsState state) {
    _state = state;
    notifyListeners();
  }
}

final class _SettingsParseResult {
  const _SettingsParseResult({this.settings, this.issues = const []});

  final AppSettings? settings;
  final List<SettingsValidationIssue> issues;
}

final class _SettingsDraft {
  const _SettingsDraft({
    required this.reminderIntervalMinutes,
    required this.autocompleteLookbackDays,
    required this.responseTimeoutMinutes,
    required this.typingDeferralSeconds,
    required this.startAtLogin,
    required this.capabilities,
  });

  factory _SettingsDraft.fromState(SettingsState state) {
    return _SettingsDraft(
      reminderIntervalMinutes: state.reminderIntervalMinutes,
      autocompleteLookbackDays: state.autocompleteLookbackDays,
      responseTimeoutMinutes: state.responseTimeoutMinutes,
      typingDeferralSeconds: state.typingDeferralSeconds,
      startAtLogin: state.startAtLogin,
      capabilities: state.capabilities,
    );
  }

  factory _SettingsDraft.fromSnapshot(AppStateSnapshot snapshot) {
    final settings = snapshot.settings;
    return _SettingsDraft(
      reminderIntervalMinutes: settings.reminderIntervalMinutes.toString(),
      autocompleteLookbackDays: settings.autocompleteLookbackDays.toString(),
      responseTimeoutMinutes: settings.responseTimeoutMinutes.toString(),
      typingDeferralSeconds: settings.typingDeferralSeconds.toString(),
      startAtLogin:
          snapshot.capabilities.supportsStartAtLogin && settings.startAtLogin,
      capabilities: snapshot.capabilities,
    );
  }

  final String reminderIntervalMinutes;
  final String autocompleteLookbackDays;
  final String responseTimeoutMinutes;
  final String typingDeferralSeconds;
  final bool startAtLogin;
  final PlatformCapabilities capabilities;

  SettingsState toState({required bool isOpen}) {
    return SettingsState(
      isOpen: isOpen,
      loading: false,
      saving: false,
      dirty: false,
      reminderIntervalMinutes: reminderIntervalMinutes,
      autocompleteLookbackDays: autocompleteLookbackDays,
      responseTimeoutMinutes: responseTimeoutMinutes,
      typingDeferralSeconds: typingDeferralSeconds,
      startAtLogin: startAtLogin,
      capabilities: capabilities,
    );
  }

  AppSettings toSettings() {
    final result = parse();
    if (result.settings == null) {
      throw StateError('Snapshot settings did not parse.');
    }
    return result.settings!;
  }

  _SettingsParseResult parse() {
    final issues = <SettingsValidationIssue>[];
    final reminderInterval = _parseWholeNumber(
      reminderIntervalMinutes,
      field: SettingsField.reminderIntervalMinutes,
      label: 'Reminder interval',
      issues: issues,
    );
    final autocompleteLookback = _parseWholeNumber(
      autocompleteLookbackDays,
      field: SettingsField.autocompleteLookbackDays,
      label: 'Autocomplete lookback',
      issues: issues,
    );
    final responseTimeout = _parseWholeNumber(
      responseTimeoutMinutes,
      field: SettingsField.responseTimeoutMinutes,
      label: 'Response timeout',
      issues: issues,
    );
    final typingDeferral = _parseWholeNumber(
      typingDeferralSeconds,
      field: SettingsField.typingDeferralSeconds,
      label: 'Typing deferral',
      issues: issues,
    );

    if (issues.isNotEmpty) {
      return _SettingsParseResult(issues: issues);
    }

    return _SettingsParseResult(
      settings: AppSettings(
        reminderIntervalMinutes: reminderInterval!,
        autocompleteLookbackDays: autocompleteLookback!,
        responseTimeoutMinutes: responseTimeout!,
        typingDeferralSeconds: typingDeferral!,
        startAtLogin: capabilities.supportsStartAtLogin && startAtLogin,
      ),
    );
  }

  bool isDirtyComparedWith(AppSettings? savedSettings) {
    final parseResult = parse();
    final settings = parseResult.settings;
    if (parseResult.issues.isNotEmpty || settings == null) {
      return true;
    }
    if (settings.validate().isNotEmpty) {
      return true;
    }

    return settings != savedSettings;
  }

  int? _parseWholeNumber(
    String value, {
    required SettingsField field,
    required String label,
    required List<SettingsValidationIssue> issues,
  }) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      issues.add(
        SettingsValidationIssue(
          field: field,
          message: '$label must be a whole number.',
        ),
      );
      return null;
    }

    return parsed;
  }
}

final class _SettingsSaveRequest {
  const _SettingsSaveRequest(this.settings, this.draftRevision);

  final AppSettings settings;
  final int draftRevision;
}
