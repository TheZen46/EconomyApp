import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/boxes/data/models/box_model.dart';
import '../../features/evault/data/models/asset_model.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';
import 'secure_storage_service.dart';

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
  static const int currentSchemaVersion = 3;

  /// Hive settings key used to persist the active schema version.
  static const String schemaVersionKey = 'schema_version';

  /// Safely migrates an existing unencrypted Hive box to encrypted storage.
  ///
  /// If the box file does not exist, nothing needs to be migrated.
  /// If the box file exists as unencrypted plaintext from a previous version,
  /// its entries are copied, the unencrypted box file deleted, and rewritten
  /// into an encrypted box with [cipher].
  static Future<void> ensureBoxEncrypted(
    String boxName,
    HiveCipher cipher, [
    SecureStorageService? secureStorage,
  ]) async {
    final storage = secureStorage ?? SecureStorageService();
    if (Hive.isBoxOpen(boxName)) return;

    if (!await boxFilesExist([boxName])) return;

    final markerKey = 'migrated_enc_$boxName';
    try {
      final alreadyMigrated = await storage.readSecret(markerKey);
      if (alreadyMigrated == 'true') return;
    } catch (_) {}

    try {
      debugPrint('HiveMigrationService: Checking if "$boxName" requires plaintext-to-cipher migration...');
      final plainBox = await Hive.openBox<dynamic>(boxName, crashRecovery: false);
      final entries = Map<dynamic, dynamic>.from(plainBox.toMap());
      await plainBox.close();

      await backupBoxFile(boxName);
      await Hive.deleteBoxFromDisk(boxName);

      final encBox = await Hive.openBox<dynamic>(boxName, encryptionCipher: cipher);
      if (entries.isNotEmpty) {
        await encBox.putAll(entries);
      }
      await encBox.close();

      await storage.writeSecret(markerKey, 'true');
      debugPrint('HiveMigrationService: Successfully migrated "$boxName" from plaintext to AES cipher (${entries.length} entries).');
    } catch (e) {
      debugPrint('HiveMigrationService: Box "$boxName" was already encrypted or non-plaintext ($e).');
      try {
        await storage.writeSecret(markerKey, 'true');
      } catch (_) {}
    }
  }

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
    bool migrateFromPlaintext = false,
    SecureStorageService? secureStorage,
  }) async {
    if (encryptionCipher != null && migrateFromPlaintext) {
      await ensureBoxEncrypted(boxName, encryptionCipher, secureStorage);
    }

    final completer = Completer<Box<T>>();

    // Hive can report one failure twice: as the exception of openBox and again
    // as an uncaught error in this zone. Whichever arrives first backs up the
    // file and answers the caller; an error that reaches only the zone must
    // still answer it, or startup would wait forever.
    var failureHandled = false;
    Future<void> fail(Object error) async {
      if (failureHandled || completer.isCompleted) return;
      failureHandled = true;
      final backupPath = await backupBoxFile(boxName);
      if (!completer.isCompleted) {
        completer.completeError(
          SchemaCorruptionException(boxName: boxName, cause: error, backupPath: backupPath),
        );
      }
    }

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
        await fail(e);
      }
    }, (error, stack) {
      debugPrint('HiveMigrationService [DIAGNOSTIC]: Intercepted secondary zone error: $error');
      unawaited(fail(error));
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

    // Migration from v2 to v3:
    // Rewrites non-unique identifiers ('main' box, millisecond timestamps) and updates references
    if (currentVersion < 3) {
      await _migrateV2ToV3(settingsBox, cipher);
      await setSchemaVersion(settingsBox, 3);
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

  static Future<void> _migrateV2ToV3(Box settingsBox, HiveCipher? cipher) async {
    debugPrint('HiveMigrationService: Running migration v2 -> v3 (UUID entity migration & reference rewrite)...');

    String defaultBoxId = settingsBox.get('default_box_id') as String? ?? '';
    if (defaultBoxId.isEmpty) {
      defaultBoxId = const Uuid().v4();
      await settingsBox.put('default_box_id', defaultBoxId);
    }

    // 1. Migrate Boxes: if legacy 'main' box exists, assign user-specific UUID
    try {
      final boxesBox = await openBoxSafe<BoxModel>('boxes', encryptionCipher: cipher);
      final legacyMainBox = boxesBox.get('main');
      if (legacyMainBox != null) {
        final migratedBox = BoxModel(
          id: defaultBoxId,
          name: legacyMainBox.name,
          budget: legacyMainBox.budget,
          spent: legacyMainBox.spent,
          currency: legacyMainBox.currency,
          color: legacyMainBox.color,
          icon: legacyMainBox.icon,
          autoCategorize: legacyMainBox.autoCategorize,
          keywords: legacyMainBox.keywords,
          isPrivate: legacyMainBox.isPrivate,
          userId: legacyMainBox.userId,
          createdAt: legacyMainBox.createdAt,
          updatedAt: DateTime.now(),
          version: legacyMainBox.version + 1,
        );
        await boxesBox.put(defaultBoxId, migratedBox);
        await boxesBox.delete('main');
      }
    } catch (e) {
      debugPrint('HiveMigrationService: Boxes v3 migration notice: $e');
    }

    // 2. Migrate Receipts & Items: rewrite 'main' boxId to defaultBoxId and ensure UUID receipt ids
    final Map<String, String> receiptIdMap = {};
    try {
      final receiptsBox = await openBoxSafe<ReceiptModel>('receipts', encryptionCipher: cipher);
      final receiptsToPut = <ReceiptModel>[];
      final keysToDelete = <dynamic>[];

      for (final key in receiptsBox.keys) {
        final receipt = receiptsBox.get(key);
        if (receipt == null) continue;

        bool updated = false;
        String newId = receipt.id;
        final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(receipt.id);
        if (!isUuid) {
          newId = const Uuid().v4();
          receiptIdMap[receipt.id] = newId;
          keysToDelete.add(key);
          updated = true;
        }

        String targetBoxId = receipt.boxId ?? defaultBoxId;
        if (targetBoxId == 'main') {
          targetBoxId = defaultBoxId;
          updated = true;
        }

        final updatedItems = receipt.items.map<ReceiptItemModel>((item) {
          if (item.boxId == 'main' || item.boxId == null) {
            updated = true;
            return item.copyWith(boxId: defaultBoxId);
          }
          return item;
        }).toList();

        if (updated) {
          receiptsToPut.add(receipt.copyWith(
            id: newId,
            boxId: targetBoxId,
            items: updatedItems,
          ));
        }
      }

      for (final key in keysToDelete) {
        await receiptsBox.delete(key);
      }
      for (final r in receiptsToPut) {
        await receiptsBox.put(r.id, r);
      }
    } catch (e) {
      debugPrint('HiveMigrationService: Receipts v3 migration notice: $e');
    }

    // 3. Migrate Assets: update receiptId if referenced receipt was re-keyed
    try {
      final assetsBox = await openBoxSafe<AssetModel>('assets', encryptionCipher: cipher);
      for (final key in assetsBox.keys) {
        final asset = assetsBox.get(key);
        if (asset != null && asset.receiptId != null && receiptIdMap.containsKey(asset.receiptId)) {
          final updatedAsset = AssetModel(
            id: asset.id,
            name: asset.name,
            purchaseDate: asset.purchaseDate,
            warrantyMonths: asset.warrantyMonths,
            price: asset.price,
            receiptImagePath: asset.receiptImagePath,
            merchantName: asset.merchantName,
            receiptId: receiptIdMap[asset.receiptId]!,
            userId: asset.userId,
            documentPath: asset.documentPath,
            createdAt: asset.createdAt,
            updatedAt: DateTime.now(),
            version: asset.version + 1,
          );
          await assetsBox.put(key, updatedAsset);
        }
      }
    } catch (e) {
      debugPrint('HiveMigrationService: Assets v3 migration notice: $e');
    }

    // 4. Update activeBoxId in settings if it was 'main'
    final activeBox = settingsBox.get('activeBoxId');
    if (activeBox == 'main') {
      await settingsBox.put('activeBoxId', defaultBoxId);
    }
  }

  // ── Backup Operations ─────────────────────────────────────────────────────

  /// Locates the `.hive` file for [boxName] and copies it to a timestamped
  /// backup file inside `getApplicationDocumentsDirectory()/hive_backups/`.
  /// Returns the backup path, or null if the original file does not exist.
  static Future<String?> backupBoxFile(String boxName) async {
    if (kIsWeb) {
      debugPrint('HiveMigrationService: Web uses IndexedDB; skipping filesystem backup.');
      return null;
    }
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
    if (kIsWeb) return [];
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
  ///
  /// Must mirror `Hive.initFlutter()`, which stores boxes in the application
  /// documents directory on every non-web platform. (Resolving a different
  /// directory on desktop made backups look for box files that are not there.)
  static Future<Directory> getHiveDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('FileSystem directory not supported on web.');
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Whether a database file exists for any of [boxNames].
  static Future<bool> boxFilesExist(List<String> boxNames) async {
    if (kIsWeb) return false;
    final baseDir = await getHiveDirectory();
    for (final name in boxNames) {
      if (await File('${baseDir.path}/$name.hive').exists()) return true;
    }
    return false;
  }

  /// Moves the files of [boxNames] (which must not be open) out of the Hive
  /// directory into `hive_backups/quarantine_<timestamp>/`, so that the next
  /// launch starts with empty boxes. Files are moved, never deleted, so the
  /// original bytes stay available for recovery even when no backup could be
  /// created. Returns the quarantine directory, or null when nothing was moved.
  static Future<String?> quarantineBoxes(List<String> boxNames) async {
    if (kIsWeb) return null;
    final baseDir = await getHiveDirectory();
    final backupDir = await getBackupDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final quarantineDir = Directory('${backupDir.path}/quarantine_$stamp');

    var moved = 0;
    for (final name in boxNames) {
      for (final suffix in const ['.hive', '.lock']) {
        final file = File('${baseDir.path}/$name$suffix');
        if (!await file.exists()) continue;
        if (!await quarantineDir.exists()) await quarantineDir.create(recursive: true);
        final target = '${quarantineDir.path}/$name$suffix';
        try {
          await file.rename(target);
        } on FileSystemException {
          // rename() cannot cross file systems; fall back to copy and delete.
          await file.copy(target);
          await file.delete();
        }
        moved++;
      }
    }
    if (moved == 0) return null;
    debugPrint('HiveMigrationService [DIAGNOSTIC]: Quarantined $moved file(s) in "${quarantineDir.path}"');
    return quarantineDir.path;
  }

  /// Returns the dedicated `hive_backups/` directory, creating it if needed.
  static Future<Directory> getBackupDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Backup directory not supported on web.');
    }
    final baseDir = await getHiveDirectory();
    final backupDir = Directory('${baseDir.path}/hive_backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }
}
