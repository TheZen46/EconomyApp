import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/services/hive_migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_dir_');
    Hive.init(tempDir.path);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HiveMigrationService Tests', () {
    test('openBoxSafe opens a box successfully on normal operation', () async {
      final box = await HiveMigrationService.openBoxSafe<String>('test_box_healthy');
      expect(box.isOpen, isTrue);

      await box.put('key1', 'value1');
      expect(box.get('key1'), 'value1');

      await box.close();
    });

    test('backupBoxFile creates a timestamped backup in hive_backups/ directory', () async {
      // 1. Create a box and write data
      final box = await Hive.openBox('test_box_backup');
      await box.put('name', 'test_data');
      await box.close();

      // 2. Perform backup
      final backupPath = await HiveMigrationService.backupBoxFile('test_box_backup');

      expect(backupPath, isNotNull);
      expect(backupPath, contains('hive_backups'));
      expect(backupPath, contains('test_box_backup_backup_'));

      final backupFile = File(backupPath!);
      expect(await backupFile.exists(), isTrue);

      final backups = await HiveMigrationService.listBackups();
      expect(backups.length, 1);
      expect(
        backups.first.path.replaceAll('\\', '/'),
        backupPath.replaceAll('\\', '/'),
      );
    });

    test('openBoxSafe creates a backup and throws SchemaCorruptionException on corruption without deleting file', () async {
      final cipher1 = HiveAesCipher(List.filled(32, 1));
      final cipher2 = HiveAesCipher(List.filled(32, 2));

      // 1. Create an encrypted box with cipher1
      final box = await Hive.openBox('encrypted_corrupt_test', encryptionCipher: cipher1);
      await box.put('important_financial_data', '42000.00 USD');
      await box.close();

      final rawBoxFile = File('${tempDir.path}/encrypted_corrupt_test.hive');
      expect(await rawBoxFile.exists(), isTrue);

      // 2. Attempt to open with wrong cipher (simulating cipher mismatch / corruption)
      SchemaCorruptionException? caughtException;
      try {
        await HiveMigrationService.openBoxSafe('encrypted_corrupt_test', encryptionCipher: cipher2);
      } on SchemaCorruptionException catch (e) {
        caughtException = e;
      }

      expect(caughtException, isNotNull);
      expect(caughtException!.boxName, 'encrypted_corrupt_test');
      expect(caughtException.backupPath, isNotNull);
      expect(caughtException.backupPath, contains('hive_backups'));

      // Original file must NOT be deleted
      expect(await rawBoxFile.exists(), isTrue);

      // Backup file must exist in hive_backups/
      final backupFile = File(caughtException.backupPath!);
      expect(await backupFile.exists(), isTrue);
    });

    test('schema version tracking and runSchemaMigrations upgrades from v1 to v2', () async {
      final settingsBox = await Hive.openBox('test_settings_box');

      // Uninitialized schema version defaults to 1
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 1);

      // Run migrations
      await HiveMigrationService.runSchemaMigrations(settingsBox);

      // Schema version should now be 2
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 2);
      expect(settingsBox.get('activeBoxId'), 'main');

      // Running again should be idempotent
      await HiveMigrationService.runSchemaMigrations(settingsBox);
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 2);

      await settingsBox.close();
    });
  });
}
