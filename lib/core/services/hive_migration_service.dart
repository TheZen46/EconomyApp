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

/// Safe Hive box opening with automatic backup on schema errors.
///
/// If a box fails to open (due to schema changes, encryption mismatch, or
/// corruption), this service:
///   1. Locates the raw `.hive` file on the filesystem.
///   2. Copies it to a timestamped backup file — no data is wiped.
///   3. Throws [SchemaCorruptionException] so the UI can present a
///      "Data Recovery" dialog to the user rather than silently losing data.
///
/// **No destructive operation is ever performed automatically.**
class HiveMigrationService {
  /// Attempts to open a Hive box safely.
  ///
  /// On success, returns the opened box.
  /// On failure, backs up the raw file and throws [SchemaCorruptionException].
  static Future<Box<T>> openBoxSafe<T>(
    String boxName, {
    HiveCipher? encryptionCipher,
  }) async {
    try {
      return await Hive.openBox<T>(
        boxName,
        encryptionCipher: encryptionCipher,
      );
    } catch (e) {
      debugPrint('HiveMigrationService: Failed to open "$boxName": $e');
      final backupPath = await _backupBoxFile(boxName);
      throw SchemaCorruptionException(
        boxName: boxName,
        cause: e,
        backupPath: backupPath,
      );
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Locates the `.hive` file for [boxName] and copies it to a timestamped
  /// backup alongside the original. Returns the backup path, or null if the
  /// backup itself fails (e.g. file not found on first-ever run).
  static Future<String?> _backupBoxFile(String boxName) async {
    try {
      final dir = await _getHiveDirectory();
      final sourceFile = File('${dir.path}/$boxName.hive');

      if (!await sourceFile.exists()) {
        debugPrint(
          'HiveMigrationService: No .hive file found for "$boxName" — '
          'this may be a first-run or the file is in a custom path.',
        );
        return null;
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupFile =
          File('${dir.path}/${boxName}_backup_$timestamp.hive');

      await sourceFile.copy(backupFile.path);

      debugPrint(
        'HiveMigrationService: Backup created at "${backupFile.path}"',
      );
      return backupFile.path;
    } catch (backupError) {
      debugPrint(
        'HiveMigrationService: Backup FAILED for "$boxName": $backupError',
      );
      return null;
    }
  }

  /// Returns the directory where Hive stores its files.
  /// On mobile this is the application documents directory.
  /// On desktop (Windows/macOS/Linux) it uses the application support directory.
  static Future<Directory> _getHiveDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return await getApplicationSupportDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }
}
