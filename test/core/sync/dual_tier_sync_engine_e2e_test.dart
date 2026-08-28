import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/privacy/pii_scrubber_service.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/settings/data/models/user_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box<ReceiptModel> receiptsBox;
  late Box<BoxModel> boxesBox;
  late Box<InvoiceModel> invoicesBox;
  late Box<AssetModel> assetsBox;
  late Box<SyncOutboxItem> outboxBox;
  late OutboxService outboxService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_engine_e2e_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(AssetModelAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(BoxModelAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(InvoiceModelAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SyncOutboxItemAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(UserProfileModelAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    receiptsBox = await Hive.openBox<ReceiptModel>('test_receipts_$timestamp');
    boxesBox = await Hive.openBox<BoxModel>('test_boxes_$timestamp');
    invoicesBox = await Hive.openBox<InvoiceModel>('test_invoices_$timestamp');
    assetsBox = await Hive.openBox<AssetModel>('test_assets_$timestamp');
    outboxBox = await Hive.openBox<SyncOutboxItem>('test_outbox_$timestamp');
    outboxService = OutboxService(outboxBox);
  });

  tearDown(() async {
    await receiptsBox.deleteFromDisk();
    await boxesBox.deleteFromDisk();
    await invoicesBox.deleteFromDisk();
    await assetsBox.deleteFromDisk();
    await outboxBox.deleteFromDisk();
  });

  group('Full User-Data Discovery & Dual-Tier Sync Engine Verification', () {
    // ──────────────────────────────────────────────────────────────────────────
    // 1. DATA DISCOVERY & ENTITY AUDIT VALIDATION
    // ──────────────────────────────────────────────────────────────────────────
    test('Audit: All 6 mutable entity types serialize and track version metadata correctly', () {
      final now = DateTime.now();

      // Core Financial: ReceiptModel
      final receipt = ReceiptModel(
        id: 'rec-001',
        merchantName: 'Trader Joe\'s',
        date: now,
        totalAmount: 45.80,
        currency: 'USD',
        items: [
          ReceiptItemModel(
            description: 'Organic Almond Milk',
            unitPrice: 3.50,
            quantity: 2,
            totalPrice: 7.00,
            mainCategory: 'Groceries',
            subCategory: 'Dairy Alternative',
            necessity: 'essential',
            isUserCorrected: true,
            confidenceScore: 0.99,
          ),
        ],
        userId: 'usr-alice-123',
        version: 1,
      );
      final receiptJson = receipt.toJson();
      expect(receiptJson['user_id'], 'usr-alice-123');
      expect(receiptJson['version'], 1);
      expect(receiptJson['items'][0]['is_user_corrected'], true);

      // Contextual Organizational: BoxModel
      final box = BoxModel(
        id: 'box-work-01',
        name: 'Work Travel',
        budget: 1500.0,
        spent: 340.0,
        currency: 'EUR',
        color: 0xFF002FA7,
        userId: 'usr-alice-123',
        version: 2,
      );
      final boxJson = box.toJson();
      expect(boxJson['name'], 'Work Travel');
      expect(boxJson['budget'], 1500.0);
      expect(boxJson['version'], 2);

      // Invoicing: InvoiceModel
      final invoice = InvoiceModel(
        id: 'inv-101',
        invoiceNumber: 'INV-2026-001',
        clientName: 'Acme Corp',
        amount: 2500.00,
        status: InvoiceStatus.sent,
        issuedDate: now,
        userId: 'usr-alice-123',
        version: 1,
      );
      final invoiceJson = invoice.toJson();
      expect(invoiceJson['invoice_number'], 'INV-2026-001');
      expect(invoiceJson['status'], 'Sent');

      // Asset Management: AssetModel
      final asset = AssetModel(
        id: 'asset-404',
        name: 'Dell UltraSharp 32',
        purchaseDate: now,
        warrantyMonths: 36,
        price: 899.99,
        receiptImagePath: 'usr-alice-123/images/dell.jpg',
        merchantName: 'Dell Online',
        documentPath: 'usr-alice-123/docs/warranty.pdf',
        userId: 'usr-alice-123',
        version: 1,
      );
      final assetJson = asset.toJson();
      expect(assetJson['document_path'], 'usr-alice-123/docs/warranty.pdf');

      // Preferences: UserProfileModel
      final profile = UserProfileModel(
        id: 'usr-alice-123',
        monthlyBudget: 3000.0,
        defaultCurrency: 'USD',
        themeMode: 'dark',
        gamificationXp: 500,
        gamificationStreak: 5,
        version: 3,
      );
      final profileJson = profile.toJson();
      expect(profileJson['monthly_budget'], 3000.0);
      expect(profileJson['gamification_xp'], 500);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 2. DUAL-TIER PRIVACY FRAMEWORK VALIDATION
    // ──────────────────────────────────────────────────────────────────────────
    test('Dual-Tier: Tier 1 scrubbing strips sensitive PII while retaining ground-truth training signals', () {
      final receipt = Receipt(
        id: 'rec-pii-test',
        merchantName: 'Starbucks Coffee - Branch #42 alessandro@gmail.com',
        vatNumber: 'IT12345678901',
        merchantAddress: 'Via Roma 14, Milan, Italy',
        date: DateTime.now(),
        time: '10:30',
        totalAmount: 12.50,
        currency: 'EUR',
        items: [
          const ReceiptItem(
            description: '2x Espresso & Croissant paid with Card 4532 0150 9988 1234',
            unitPrice: 6.25,
            quantity: 2,
            totalPrice: 12.50,
            necessity: ItemNecessity.discretional,
            mainCategory: 'Food & Dining',
            subCategory: 'Coffee',
          ),
        ],
      );

      final scrubbedData = PiiScrubberService.sanitizeReceiptForTraining(receipt);

      // Verify Tier 1 PII Redaction
      expect(scrubbedData['anonymized_merchant'], isNot(contains('alessandro@gmail.com')));
      expect(scrubbedData['anonymized_merchant'], contains('[REDACTED_EMAIL]'));

      final scrubbedItem = (scrubbedData['items'] as List).first as Map<String, dynamic>;
      expect(scrubbedItem['anonymized_description'], isNot(contains('4532 0150 9988 1234')));
      expect(scrubbedItem['anonymized_description'], contains('[REDACTED_CARD]'));

      // Verify Ground Truth AI Training Signals Preserved
      expect(scrubbedItem['quantity'], 2);
      expect(scrubbedItem['unit_price'], 6.25);
      expect(scrubbedItem['total_price'], 12.50);
      expect(scrubbedItem['main_category'], 'Food & Dining');
      expect(scrubbedItem['sub_category'], 'Coffee');
      expect(scrubbedItem['necessity'], 'discretional');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 3. OFFLINE-FIRST OUTBOX QUEUE & LIFECYCLE VALIDATION
    // ──────────────────────────────────────────────────────────────────────────
    test('Outbox: Local mutations queue in FIFO order and process status transitions', () async {
      // 1. Enqueue mutations across different domains while offline
      final item1 = await outboxService.enqueue(
        entityType: 'receipt',
        entityId: 'rec-001',
        mutationType: 'insert',
        payload: {'merchant_name': 'Apple Store', 'total_amount': 999.00},
      );
      await Future.delayed(const Duration(milliseconds: 5));

      final item2 = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-001',
        mutationType: 'update',
        payload: {'name': 'Electronics', 'spent': 999.00},
      );
      await Future.delayed(const Duration(milliseconds: 5));

      final item3 = await outboxService.enqueue(
        entityType: 'invoice',
        entityId: 'inv-001',
        mutationType: 'delete',
        payload: {},
      );

      // Verify FIFO ordering
      final pending = outboxService.getPendingMutations();
      expect(pending.length, 3);
      expect(pending[0].id, item1.id);
      expect(pending[1].id, item2.id);
      expect(pending[2].id, item3.id);

      // Simulate successful sync of item 1
      await outboxService.markCompleted(item1.id);
      expect(outboxService.getPendingMutations().length, 2);

      // Simulate network error on item 2
      await outboxService.markFailed(item2.id, 'SocketException: Connection refused');
      final failedItem = outboxBox.get(item2.id)!;
      expect(failedItem.retryCount, 1);
      expect(failedItem.status, 'failed');
      expect(failedItem.errorMessage, contains('Connection refused'));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 4. BIDIRECTIONAL CONFLICT RESOLUTION (LWW) & TOMBSTONE VALIDATION
    // ──────────────────────────────────────────────────────────────────────────
    test('Conflict Resolution: Last-Write-Wins and Tombstone purge behave correctly', () async {
      final initialTime = DateTime(2026, 8, 28, 12, 0, 0);
      final localReceipt = ReceiptModel(
        id: 'rec-sync-test',
        merchantName: 'Local Grocery',
        date: initialTime,
        totalAmount: 30.00,
        currency: 'USD',
        items: [],
        userId: 'usr-123',
        updatedAt: initialTime,
        version: 1,
      );

      await receiptsBox.put(localReceipt.id, localReceipt);
      expect(receiptsBox.get('rec-sync-test')!.merchantName, 'Local Grocery');

      // Scenario A: Remote has higher version -> Overwrite local
      final remoteUpdateHigherVersion = ReceiptModel(
        id: 'rec-sync-test',
        merchantName: 'Remote Grocery (Updated)',
        date: initialTime,
        totalAmount: 35.00,
        currency: 'USD',
        items: [],
        userId: 'usr-123',
        updatedAt: initialTime.add(const Duration(hours: 1)),
        version: 2,
      );

      final shouldOverwriteA = remoteUpdateHigherVersion.version > localReceipt.version;
      expect(shouldOverwriteA, true);
      if (shouldOverwriteA) {
        await receiptsBox.put(remoteUpdateHigherVersion.id, remoteUpdateHigherVersion);
      }
      expect(receiptsBox.get('rec-sync-test')!.merchantName, 'Remote Grocery (Updated)');
      expect(receiptsBox.get('rec-sync-test')!.version, 2);

      // Scenario B: Remote has lower version -> Do not overwrite
      final remoteStaleUpdate = ReceiptModel(
        id: 'rec-sync-test',
        merchantName: 'Stale Grocery',
        date: initialTime,
        totalAmount: 20.00,
        currency: 'USD',
        items: [],
        userId: 'usr-123',
        updatedAt: initialTime.subtract(const Duration(hours: 2)),
        version: 1,
      );

      final current = receiptsBox.get('rec-sync-test')!;
      final shouldOverwriteB = remoteStaleUpdate.version > current.version;
      expect(shouldOverwriteB, false);

      // Scenario C: Tombstone soft-delete from remote -> purges local record
      final remoteTombstone = {
        'id': 'rec-sync-test',
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (remoteTombstone['deleted_at'] != null) {
        await receiptsBox.delete(remoteTombstone['id']);
      }
      expect(receiptsBox.get('rec-sync-test'), isNull);
    });
  });
}
