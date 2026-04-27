import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class AppDatabase {
  AppDatabase._(this.database);

  static const schemaVersion = 1;
  static const databaseFileName = 'wyd.sqlite';

  static bool _ffiInitialized = false;

  final Database database;

  static Future<AppDatabase> openDefault({
    DatabaseFactory? databaseFactory,
  }) async {
    final path = await defaultDatabasePath();
    return openAtPath(path, databaseFactory: databaseFactory);
  }

  static Future<AppDatabase> openAtPath(
    String databasePath, {
    DatabaseFactory? databaseFactory,
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
  }) async {
    return openAtPath(inMemoryDatabasePath, databaseFactory: databaseFactory);
  }

  static Future<String> defaultDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    return p.join(directory.path, databaseFileName);
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
  clean_shutdown INTEGER NOT NULL DEFAULT 1 CHECK(clean_shutdown IN (0, 1))
)
''');

    await database.insert('app_state', {
      'id': 1,
      'pending_prompt_expired': 0,
      'clean_shutdown': 1,
    });

    await database.execute('''
CREATE TABLE settings (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  reminder_interval_minutes INTEGER NOT NULL,
  autocomplete_lookback_days INTEGER NOT NULL,
  response_timeout_minutes INTEGER NOT NULL,
  typing_deferral_seconds INTEGER NOT NULL,
  start_at_login INTEGER NOT NULL CHECK(start_at_login IN (0, 1))
)
''');
  }

  static Future<void> _upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    throw UnsupportedError(
      'Unsupported database migration from $oldVersion to $newVersion.',
    );
  }
}
