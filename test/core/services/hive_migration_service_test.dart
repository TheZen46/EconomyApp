import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/services/hive_migration_service.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('hive_test_dir_');
    Hive.init(tempDir.path);

    // Hive.init above mirrors Hive.initFlutter, which uses the documents
    // directory; the support directory is deliberately different so that code
    // resolving the wrong directory is detected.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportDirectory') {
          return '${tempDir.path}/support';
        }
        return tempDir.path;
      },
    );
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(AssetModelAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(BoxModelAdapter());
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

    test('schema version tracking and runSchemaMigrations upgrades from v1 to v3', () async {
      final settingsBox = await Hive.openBox('test_settings_box');

      // Uninitialized schema version defaults to 1
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 1);

      // Run migrations
      await HiveMigrationService.runSchemaMigrations(settingsBox);

      // Schema version should now be 3
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 3);
      expect(settingsBox.get('activeBoxId'), isNotNull);

      // Running again should be idempotent
      await HiveMigrationService.runSchemaMigrations(settingsBox);
      expect(HiveMigrationService.getSchemaVersion(settingsBox), 3);

      await settingsBox.close();
    });

    test('v2 to v3 migration rewrites legacy main box to UUID and updates receipt and asset references', () async {
      final settingsBox = await Hive.openBox('settings');
      await settingsBox.put(HiveMigrationService.schemaVersionKey, 2);
      await settingsBox.put('activeBoxId', 'main');

      // 1. Seed legacy 'main' box
      final boxesBox = await Hive.openBox<BoxModel>('boxes');
      final legacyBox = BoxModel(
        id: 'main',
        name: 'Main Life',
        budget: 500,
        spent: 100,
        currency: 'USD',
        color: 0xFF000000,
      );
      await boxesBox.put('main', legacyBox);

      // 2. Seed legacy receipt with non-UUID id and 'main' boxId
      final receiptsBox = await Hive.openBox<ReceiptModel>('receipts');
      const legacyReceiptId = 'vlm_1728900000000';
      final legacyReceipt = ReceiptModel(
        id: legacyReceiptId,
        merchantName: 'Acme Corp',
        date: DateTime(2026, 1, 1),
        totalAmount: 42.50,
        currency: 'USD',
        boxId: 'main',
        items: [
          ReceiptItemModel(
            description: 'Item 1',
            unitPrice: 42.50,
            quantity: 1,
            totalPrice: 42.50,
            boxId: 'main',
          ),
        ],
      );
      await receiptsBox.put(legacyReceiptId, legacyReceipt);

      // 3. Seed asset referencing legacy receipt id
      final assetsBox = await Hive.openBox<AssetModel>('assets');
      final legacyAsset = AssetModel(
        id: 'asset_1',
        name: 'Laptop',
        purchaseDate: DateTime(2026, 1, 1),
        warrantyMonths: 24,
        price: 42.50,
        receiptImagePath: '',
        merchantName: 'Acme Corp',
        receiptId: legacyReceiptId,
      );
      await assetsBox.put('asset_1', legacyAsset);

      // Close boxes so migration opens them via openBoxSafe
      await boxesBox.close();
      await receiptsBox.close();
      await assetsBox.close();

      // Run migration
      await HiveMigrationService.runSchemaMigrations(settingsBox);

      expect(HiveMigrationService.getSchemaVersion(settingsBox), 3);
      final defaultBoxId = settingsBox.get('default_box_id') as String;
      expect(defaultBoxId, isNotEmpty);
      expect(defaultBoxId, isNot('main'));
      expect(settingsBox.get('activeBoxId'), defaultBoxId);

      // Verify boxes
      final reopenedBoxes = await Hive.openBox<BoxModel>('boxes');
      expect(reopenedBoxes.get('main'), isNull);
      final migratedBox = reopenedBoxes.get(defaultBoxId);
      expect(migratedBox, isNotNull);
      expect(migratedBox!.id, defaultBoxId);
      expect(migratedBox.name, 'Main Life');

      // Verify receipts
      final reopenedReceipts = await Hive.openBox<ReceiptModel>('receipts');
      expect(reopenedReceipts.get(legacyReceiptId), isNull);
      expect(reopenedReceipts.length, 1);
      final migratedReceipt = reopenedReceipts.values.first;
      expect(migratedReceipt.boxId, defaultBoxId);
      expect(migratedReceipt.items.first.boxId, defaultBoxId);
      expect(RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(migratedReceipt.id), isTrue);

      // Verify assets
      final reopenedAssets = await Hive.openBox<AssetModel>('assets');
      final migratedAsset = reopenedAssets.get('asset_1');
      expect(migratedAsset, isNotNull);
      expect(migratedAsset!.receiptId, migratedReceipt.id);

      await reopenedBoxes.close();
      await reopenedReceipts.close();
      await reopenedAssets.close();
      await settingsBox.close();
    });
  });

  group('HiveMigrationService recovery', () {
    test('backups find box files in the directory Hive.initFlutter uses', () async {
      final box = await Hive.openBox('desktop_box');
      await box.put('k', 'v');
      await box.close();

      final backupPath = await HiveMigrationService.backupBoxFile('desktop_box');

      expect(backupPath, isNotNull);
    });

    test('quarantining a box that cannot be opened lets it start empty', () async {
      final cipher1 = HiveAesCipher(List.filled(32, 1));
      final cipher2 = HiveAesCipher(List.filled(32, 2));
      final box = await Hive.openBox('locked_box', encryptionCipher: cipher1);
      await box.put('amount', '42.00');
      await box.close();
      final originalBytes = await File('${tempDir.path}/locked_box.hive').readAsBytes();

      await expectLater(
        HiveMigrationService.openBoxSafe('locked_box', encryptionCipher: cipher2),
        throwsA(isA<SchemaCorruptionException>()),
      );

      final quarantinePath = await HiveMigrationService.quarantineBoxes(['locked_box']);

      expect(quarantinePath, isNotNull);
      expect(await File('${tempDir.path}/locked_box.hive').exists(), isFalse);
      expect(await File('$quarantinePath/locked_box.hive').readAsBytes(), originalBytes);
      expect(await HiveMigrationService.boxFilesExist(['locked_box']), isFalse);

      final reopened = await HiveMigrationService.openBoxSafe('locked_box', encryptionCipher: cipher2);
      expect(reopened.isEmpty, isTrue);
      await reopened.close();
    });

    test('boxFilesExist and quarantineBoxes ignore boxes without files', () async {
      expect(await HiveMigrationService.boxFilesExist(['never_created']), isFalse);
      expect(await HiveMigrationService.quarantineBoxes(['never_created']), isNull);
    });

    test('ensureBoxEncrypted migrates legacy plaintext box to AES cipher box without loss', () async {
      // 1. Create a plaintext box and write sensitive data
      final plainBox = await Hive.openBox<dynamic>('settings_legacy');
      await plainBox.put('balance', 12500.50);
      await plainBox.put('tax_rate', 0.22);
      await plainBox.close();

      // 2. Open via openBoxSafe with encryptionCipher and migrateFromPlaintext: true
      final cipher = HiveAesCipher(List.filled(32, 7));
      final secureBox = await HiveMigrationService.openBoxSafe<dynamic>(
        'settings_legacy',
        encryptionCipher: cipher,
        migrateFromPlaintext: true,
      );

      // 3. Verify all data was migrated and accessible
      expect(secureBox.get('balance'), 12500.50);
      expect(secureBox.get('tax_rate'), 0.22);
      await secureBox.close();

      // 4. Verify box is physically encrypted on disk (opening without cipher fails with corruption exception)
      await expectLater(
        HiveMigrationService.openBoxSafe<dynamic>('settings_legacy'),
        throwsA(isA<SchemaCorruptionException>()),
      );
    });
  });
}
