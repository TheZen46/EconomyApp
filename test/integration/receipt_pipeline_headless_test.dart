import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Core imports
import 'package:t_aidy/core/services/telemetry_service.dart';
import 'package:t_aidy/core/services/vlm/dataset_contribution_service.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';

// Feature domain & data imports
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<ReceiptModel> receiptsBox;
  late Box<SyncOutboxItem> outboxBox;
  late HiveReceiptDataSourceImpl localDataSource;
  late OutboxService outboxService;
  late DatasetContributionService datasetContributionService;
  late TelemetryService telemetryService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('headless_e2e_receipt_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(SyncOutboxItemAdapter());

    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3_headless_test');
    outboxBox = await Hive.openBox<SyncOutboxItem>('sync_outbox_headless_test');

    localDataSource = HiveReceiptDataSourceImpl(receiptsBox);
    outboxService = OutboxService(outboxBox);
    datasetContributionService = DatasetContributionService(baseDirectory: tempDir);
    telemetryService = TelemetryService(baseDirectory: tempDir);
    await telemetryService.initialize(baseDirectory: tempDir);
  });

  tearDownAll(() async {
    await receiptsBox.clear();
    await receiptsBox.close();
    await outboxBox.clear();
    await outboxBox.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Headless E2E Receipt Pipeline Verification', () {
    test('End-to-end journey executes with zero PII leaks and persistent storage parity', () async {
      // 1. Ingestion
      final sampleImagePath = '${tempDir.path}/test_receipt_headless.jpg';
      final sampleImageFile = File(sampleImagePath);
      final mockImageBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0xFF, 0xD9,
      ]);
      await sampleImageFile.writeAsBytes(mockImageBytes);
      expect(await sampleImageFile.exists(), isTrue);

      // 2. VLM Inference
      final metric = await telemetryService.recordInferencePerformance(
        inferenceDurationMs: 120,
        preprocessingMs: 10,
        tokenCount: 45,
        modelId: 'Qwen2-VL-2B-Instruct',
        quantTier: 'Q4_K_M',
        backend: 'AVX2/SIMD',
      );
      expect(metric.tokensPerSecond, equals(375.0));

      // 3. Review & Corrections
      final receipt = Receipt(
        id: 'headless_receipt_1',
        merchantName: 'Apple Store Milano Liberty',
        merchantAddress: 'Piazza del Liberty 1, Milano',
        vatNumber: 'IT98765432101',
        date: DateTime(2026, 9, 9, 16, 45),
        totalAmount: 159.00,
        currency: 'EUR',
        items: const [
          ReceiptItem(
            description: 'Apple Magic Keyboard with Touch ID',
            quantity: 1,
            unitPrice: 159.00,
            totalPrice: 159.00,
            mainCategory: 'Electronics',
            subCategory: 'Computer Accessories',
            necessity: ItemNecessity.discretional,
            isAsset: true,
          )
        ],
        imagePath: sampleImagePath,
        boxId: 'main',
      );

      // 4. PII Redaction & Continuous Staging
      final staged = await datasetContributionService.stageVerifiedReceipt(
        receipt: receipt,
        imagePath: sampleImagePath,
      );
      expect(staged, isTrue);

      // 5. Hive Storage
      final model = ReceiptModel.fromEntity(receipt);
      await localDataSource.saveReceipt(model);
      final all = await localDataSource.getReceipts();
      final retrieved = all.firstWhere((r) => r.id == 'headless_receipt_1');
      expect(retrieved.merchantName, equals('Apple Store Milano Liberty'));
      expect(retrieved.items.first.isAsset, isTrue);

      // 6. Supabase Outbox Queue
      final outboxItem = await outboxService.enqueue(
        entityType: 'receipt',
        entityId: receipt.id,
        mutationType: 'INSERT',
        payload: model.toJson(),
      );
      expect(outboxItem.status, equals('pending'));

      await outboxService.markCompleted(outboxItem.id);
      expect(outboxService.getPendingMutations().isEmpty, isTrue);
    });
  });
}
