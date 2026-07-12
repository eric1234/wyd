import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/domain.dart';

final class AppDatabase {
  AppDatabase._(this.database);

  static const schemaVersion = 3;
  static const databaseFileName = 'wyd.sqlite';
  static const _databaseSidecarSuffixes = ['-wal', '-shm', '-journal'];

  static bool _ffiInitialized = false;

  final Database database;

  static Future<AppDatabase> openDefault({
    DatabaseFactory? databaseFactory,
    int schemaVersion = AppDatabase.schemaVersion,
  }) async {
    final path = await defaultDatabasePath();
    return openAtPath(
      path,
      databaseFactory: databaseFactory,
      schemaVersion: schemaVersion,
    );
  }

  static Future<AppDatabase> openAtPath(
    String databasePath, {
    DatabaseFactory? databaseFactory,
    int schemaVersion = AppDatabase.schemaVersion,
  }) async {
    _ensureFfiInitialized();
    final factory = databaseFactory ?? databaseFactoryFfi;
    final database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _configureDatabase,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        singleInstance: false,
      ),
    );

    return AppDatabase._(database);
  }

  static Future<AppDatabase> openInMemory({
    DatabaseFactory? databaseFactory,
    int schemaVersion = AppDatabase.schemaVersion,
  }) async {
    return openAtPath(
      inMemoryDatabasePath,
      databaseFactory: databaseFactory,
      schemaVersion: schemaVersion,
    );
  }

  static Future<String> defaultDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    return p.join(directory.path, databaseFileName);
  }

  static List<String> databaseFilePathsFor(String databasePath) {
    return [
      databasePath,
      for (final suffix in _databaseSidecarSuffixes) '$databasePath$suffix',
    ];
  }

  static Future<void> deleteDatabaseFiles(String databasePath) async {
    for (final filePath in databaseFilePathsFor(databasePath)) {
      final file = File(filePath);
      if (!await file.exists()) {
        continue;
      }

      try {
        await file.delete();
      } on FileSystemException {
        if (await file.exists()) {
          rethrow;
        }
      }
    }
  }

  Future<T> transaction<T>(Future<T> Function(Transaction transaction) action) {
    return database.transaction(action);
  }

  Future<void> close() {
    return database.close();
  }

  static void _ensureFfiInitialized() {
    if (_ffiInitialized) {
      return;
    }

    sqfliteFfiInit();
    _ffiInitialized = true;
  }

  static Future<void> _configureDatabase(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
    await database.rawQuery('PRAGMA journal_mode = WAL');
    await database.execute('PRAGMA busy_timeout = 5000');
  }

  static Future<void> _createDatabase(Database database, int version) async {
    await database.execute('''
CREATE TABLE activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  occurred_at_utc TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK(event_type IN ('start_task', 'switch_task', 'stop_task')),
  task_text TEXT,
  task_text_normalized TEXT,
  source TEXT NOT NULL CHECK(source IN (
    'manual_submit',
    'manual_stop',
    'nag_timeout',
    'system_lock',
    'system_sleep',
    'exit',
    'recovery'
  )),
  created_at_utc TEXT NOT NULL,
  CHECK (
    (event_type = 'stop_task' AND task_text IS NULL AND task_text_normalized IS NULL)
    OR
    (event_type IN ('start_task', 'switch_task') AND task_text IS NOT NULL AND task_text_normalized IS NOT NULL)
  )
)
''');

    await database.execute('''
CREATE INDEX idx_activity_log_occurred_id
ON activity_log (occurred_at_utc, id)
''');

    await database.execute('''
CREATE INDEX idx_activity_log_event_type_occurred
ON activity_log (event_type, occurred_at_utc)
''');

    await database.execute('''
CREATE TABLE app_state (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  last_confirmation_at_utc TEXT,
  pending_prompt_shown_at_utc TEXT,
  pending_prompt_expired INTEGER NOT NULL DEFAULT 0 CHECK(pending_prompt_expired IN (0, 1)),
  clean_shutdown INTEGER NOT NULL DEFAULT 1 CHECK(clean_shutdown IN (0, 1)),
  CHECK (pending_prompt_expired = 0 OR pending_prompt_shown_at_utc IS NOT NULL)
)
''');

    await database.insert('app_state', {
      'id': 1,
      'pending_prompt_expired': 0,
      'clean_shutdown': 1,
    });

    await _createSettingsTable(database);
    await _createTaskTagsTable(database);
  }

  static Future<void> _upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (newVersion != schemaVersion) {
      throw UnsupportedError(
        'Unsupported database migration from $oldVersion to $newVersion.',
      );
    }

    var currentVersion = oldVersion;
    if (currentVersion < 2) {
      await _upgradeToV2(database);
      currentVersion = 2;
    }

    if (currentVersion < 3) {
      await _upgradeToV3(database);
      currentVersion = 3;
    }

    if (currentVersion == newVersion) {
      return;
    }

    throw UnsupportedError(
      'Unsupported database migration from $oldVersion to $newVersion.',
    );
  }

  static Future<void> _upgradeToV2(Database database) async {
    await database.execute('ALTER TABLE settings RENAME TO settings_v1');
    await _createSettingsTable(database);
    await database.execute('''
INSERT INTO settings (
  id,
  reminder_interval_minutes,
  autocomplete_lookback_days,
  response_timeout_minutes,
  typing_deferral_seconds,
  start_at_login
)
SELECT
  id,
  reminder_interval_minutes,
  autocomplete_lookback_days,
  response_timeout_minutes,
  typing_deferral_seconds,
  start_at_login
FROM settings_v1
''');
    await database.execute('DROP TABLE settings_v1');
  }

  static Future<void> _upgradeToV3(Database database) async {
    await _createTaskTagsTable(database);
  }

  static Future<void> _createSettingsTable(Database database) async {
    await database.execute('''
CREATE TABLE settings (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  reminder_interval_minutes INTEGER NOT NULL CHECK(reminder_interval_minutes BETWEEN ${AppSettings.minReminderIntervalMinutes} AND ${AppSettings.maxReminderIntervalMinutes}),
  autocomplete_lookback_days INTEGER NOT NULL CHECK(autocomplete_lookback_days BETWEEN ${AppSettings.minAutocompleteLookbackDays} AND ${AppSettings.maxAutocompleteLookbackDays}),
  response_timeout_minutes INTEGER NOT NULL CHECK(response_timeout_minutes BETWEEN ${AppSettings.minResponseTimeoutMinutes} AND ${AppSettings.maxResponseTimeoutMinutes}),
  typing_deferral_seconds INTEGER NOT NULL CHECK(typing_deferral_seconds BETWEEN ${AppSettings.minTypingDeferralSeconds} AND ${AppSettings.maxTypingDeferralSeconds}),
  start_at_login INTEGER NOT NULL CHECK(start_at_login IN (0, 1)),
  CHECK (reminder_interval_minutes >= response_timeout_minutes)
)
''');
  }

  static Future<void> _createTaskTagsTable(Database database) async {
    await database.execute('''
CREATE TABLE task_tags (
  task_text_normalized TEXT NOT NULL,
  tag_text TEXT NOT NULL,
  tag_text_normalized TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  PRIMARY KEY (task_text_normalized, tag_text_normalized),
  CHECK (length(task_text_normalized) > 0),
  CHECK (length(tag_text) > 0 AND length(tag_text) <= ${TaskTag.maxLength}),
  CHECK (length(tag_text_normalized) > 0 AND length(tag_text_normalized) <= ${TaskTag.maxLength})
)
''');

    await database.execute('''
CREATE INDEX idx_task_tags_tag_text_normalized
ON task_tags (tag_text_normalized, task_text_normalized)
''');
  }
}
