import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

// ── Exception Types ──────────────────────────────────────────────────────────

/// Thrown when a Hive box cannot be opened due to schema corruption or
/// an encryption mismatch. Contains the path of the backup file that was
/// created before any destructive action could occur.
class SchemaCorruptionException implements Exception {
  final String boxName;
  final String? backupPath;
  final Object cause;

  const SchemaCorruptionException({
    required this.boxName,
    required this.cause,
    this.backupPath,
  });

  @override
  String toString() {
    final backup = backupPath != null
        ? '\nBackup saved at: $backupPath'
        : '\nBackup could not be created.';
    return 'SchemaCorruptionException(box: $boxName): $cause$backup';
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

/// Safe Hive box opening with automatic backup on schema errors and versioned
/// schema migrations.
///
/// If a box fails to open (due to schema changes, encryption mismatch, or
/// corruption), this service:
///   1. Locates the raw `.hive` file on the filesystem.
///   2. Copies it to a timestamped backup in `hive_backups/` — no data is wiped.
///   3. Logs the incident to diagnostics.
///   4. Throws [SchemaCorruptionException] so the UI can present a
///      "Data Recovery" dialog to the user rather than silently losing data.
///
/// **No destructive operation is ever performed automatically.**
class HiveMigrationService {
  /// Current target schema version of the database.
  static const int currentSchemaVersion = 2;

  /// Hive settings key used to persist the active schema version.
  static const String schemaVersionKey = 'schema_version';

  /// Attempts to open a Hive box safely.
  ///
  /// On success, returns the opened box.
  /// On failure (e.g. corruption, cipher mismatch, schema breaking change),
  /// backs up the raw file to `hive_backups/` and throws [SchemaCorruptionException].
  ///
  /// Note: [crashRecovery] defaults to `false` so Hive does not silently
  /// truncate or drop unreadable frames without creating a diagnostic backup first.
  static Future<Box<T>> openBoxSafe<T>(
    String boxName, {
    HiveCipher? encryptionCipher,
    bool crashRecovery = false,
  }) async {
    final completer = Completer<Box<T>>();

    unawaited(runZonedGuarded(() async {
      try {
        final box = await Hive.openBox<T>(
          boxName,
          encryptionCipher: encryptionCipher,
          crashRecovery: crashRecovery,
        );
        if (!completer.isCompleted) {
          completer.complete(box);
        }
      } catch (e) {
        debugPrint('HiveMigrationService [DIAGNOSTIC]: Failed to open "$boxName": $e');
        final backupPath = await backupBoxFile(boxName);
        if (!completer.isCompleted) {
          completer.completeError(
            SchemaCorruptionException(
              boxName: boxName,
              cause: e,
              backupPath: backupPath,
            ),
          );
        }
      }
    }, (error, stack) {
      // Intercept unhandled async errors from Hive's internal dual-throw
      debugPrint('HiveMigrationService [DIAGNOSTIC]: Intercepted secondary zone error: $error');
    }));

    return completer.future;
  }

  // ── Schema Versioning & Migrations ────────────────────────────────────────

  /// Returns the currently installed schema version from [settingsBox].
  /// Defaults to 1 if unset (legacy installations).
  static int getSchemaVersion(Box settingsBox) {
    final version = settingsBox.get(schemaVersionKey);
    if (version is int) return version;
    return 1;
  }

  /// Sets the recorded schema version in [settingsBox].
  static Future<void> setSchemaVersion(Box settingsBox, int version) async {
    await settingsBox.put(schemaVersionKey, version);
  }

  /// Runs all pending structured schema migrations up to [currentSchemaVersion].
  static Future<void> runSchemaMigrations(
    Box settingsBox, {
    HiveCipher? cipher,
  }) async {
    final currentVersion = getSchemaVersion(settingsBox);

    if (currentVersion >= currentSchemaVersion) {
      debugPrint('HiveMigrationService: Schema is up-to-date (v$currentVersion).');
      return;
    }

    debugPrint(
      'HiveMigrationService: Migrating schema from v$currentVersion to v$currentSchemaVersion...',
    );

    // Migration from v1 to v2:
    // Ensure boxId backwards-compatibility and legacy key cleanups
    if (currentVersion < 2) {
      await _migrateV1ToV2(settingsBox, cipher);
      await setSchemaVersion(settingsBox, 2);
    }

    debugPrint(
      'HiveMigrationService: Successfully completed migrations to v$currentSchemaVersion.',
    );
  }

  static Future<void> _migrateV1ToV2(Box settingsBox, HiveCipher? cipher) async {
    debugPrint('HiveMigrationService: Running migration v1 -> v2 (box tagging & schema cleanup)...');
    // Ensure default activeBox is initialized
    if (!settingsBox.containsKey('activeBoxId')) {
      await settingsBox.put('activeBoxId', 'main');
    }
  }

  // ── Backup Operations ─────────────────────────────────────────────────────

  /// Locates the `.hive` file for [boxName] and copies it to a timestamped
  /// backup file inside `getApplicationDocumentsDirectory()/hive_backups/`.
  /// Returns the backup path, or null if the original file does not exist.
  static Future<String?> backupBoxFile(String boxName) async {
    try {
      final baseDir = await getHiveDirectory();
      final sourceFile = File('${baseDir.path}/$boxName.hive');

      if (!await sourceFile.exists()) {
        debugPrint(
          'HiveMigrationService: No .hive file found for "$boxName" at "${sourceFile.path}"',
        );
        return null;
      }

      final backupDir = await getBackupDirectory();
      final now = DateTime.now();
      final timestamp = '${now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}_${now.microsecondsSinceEpoch}';
      var backupFile = File('${backupDir.path}/${boxName}_backup_$timestamp.hive');
      int collisionCounter = 1;
      while (await backupFile.exists()) {
        backupFile = File('${backupDir.path}/${boxName}_backup_${timestamp}_$collisionCounter.hive');
        collisionCounter++;
      }

      await sourceFile.copy(backupFile.path);

      debugPrint(
        'HiveMigrationService [DIAGNOSTIC]: Automated backup created at "${backupFile.path}"',
      );
      return backupFile.path;
    } catch (backupError) {
      debugPrint(
        'HiveMigrationService [DIAGNOSTIC]: Backup FAILED for "$boxName": $backupError',
      );
      return null;
    }
  }

  /// Lists all automated backups stored in `hive_backups/`.
  static Future<List<File>> listBackups() async {
    try {
      final backupDir = await getBackupDirectory();
      if (!await backupDir.exists()) return [];
      final entities = backupDir.listSync();
      return entities.whereType<File>().toList();
    } catch (e) {
      debugPrint('HiveMigrationService: Error listing backups: $e');
      return [];
    }
  }

  /// Returns the directory where Hive stores its primary database files.
  static Future<Directory> getHiveDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return await getApplicationSupportDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Returns the dedicated `hive_backups/` directory, creating it if needed.
  static Future<Directory> getBackupDirectory() async {
    final baseDir = await getHiveDirectory();
    final backupDir = Directory('${baseDir.path}/hive_backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }
}
