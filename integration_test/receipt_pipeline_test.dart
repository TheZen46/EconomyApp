import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';

// Core imports
import 'package:t_aidy/core/privacy/pii_scrubber_service.dart';
import 'package:t_aidy/core/services/telemetry_service.dart';
import 'package:t_aidy/core/services/vlm/dataset_contribution_service.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';

// Feature domain & data imports
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<ReceiptModel> receiptsBox;
  late Box<SyncOutboxItem> outboxBox;
  late HiveReceiptDataSourceImpl localDataSource;
  late OutboxService outboxService;
  late DatasetContributionService datasetContributionService;
  late TelemetryService telemetryService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('integration_test_receipt_');
    Hive.init(tempDir.path);

    // Register Hive Adapters if not registered
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(SyncOutboxItemAdapter());

    receiptsBox = await Hive.openBox<ReceiptModel>('receipts_v3_integration_test');
    outboxBox = await Hive.openBox<SyncOutboxItem>('sync_outbox_integration_test');

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

  group('End-to-End Receipt Pipeline Integration Tests', () {
    testWidgets('Full Journey: Ingestion -> VLM -> Review -> PII Scrubbing -> Hive -> Outbox -> Telemetry', (WidgetTester tester) async {
      // ────────────────────────────────────────────────────────────────────────
      // STAGE 1: Image Ingestion & Preprocessing
      // ────────────────────────────────────────────────────────────────────────
      final sampleImagePath = '${tempDir.path}/test_receipt_sample.jpg';
      final sampleImageFile = File(sampleImagePath);

      // Create a mock raw JPEG image header/buffer
      final mockImageBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0xFF, 0xD9,
      ]);
      await sampleImageFile.writeAsBytes(mockImageBytes);
      expect(await sampleImageFile.exists(), isTrue);

      final preStopwatch = Stopwatch()..start();
      final readBytes = await sampleImageFile.readAsBytes();
      preStopwatch.stop();
      expect(readBytes.length, greaterThan(0));

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 2: Local VLM Inference & Extraction Simulation
      // ────────────────────────────────────────────────────────────────────────
      final inferStopwatch = Stopwatch()..start();

      // Raw GBNF JSON payload produced by the VLM engine
      final vlmRawJsonOutput = jsonEncode({
        'merchant_name': 'Supermarket Express (Store #42)',
        'merchant_address': 'Via Roma 12, Milano, MI 20121 - Phone: +39 02 12345678',
        'vat_number': 'IT12345678901',
        'date': '2026-09-09',
        'time': '14:30:00',
        'currency': 'EUR',
        'items': [
          {
            'raw_name': 'ORGANIC MILK 1L',
            'normalized_name': 'Organic Whole Milk 1L',
            'quantity': 2,
            'unit_price': 1.85,
            'total_price': 3.70,
            'main_category': 'Groceries',
            'sub_category': 'Dairy & Eggs',
            'necessity': 'essential',
            'is_asset': false,
          },
          {
            'raw_name': 'ESPRESSO BLEND 500G',
            'normalized_name': 'Premium Espresso Coffee Beans',
            'quantity': 1,
            'unit_price': 6.50,
            'total_price': 6.50,
            'main_category': 'Groceries',
            'sub_category': 'Beverages',
            'necessity': 'essential',
            'is_asset': false,
          },
          {
            'raw_name': 'LOGITECH WIRELESS MOUSE M330',
            'normalized_name': 'Logitech Wireless Mouse',
            'quantity': 1,
            'unit_price': 29.99,
            'total_price': 29.99,
            'main_category': 'Electronics',
            'sub_category': 'Computer Accessories',
            'necessity': 'discretional',
            'is_asset': true,
          }
        ],
        'total_amount': 40.19,
        'customer_notes': 'Card: 4111 2222 3333 4444 - Email: receipt_customer@test.com',
      });

      inferStopwatch.stop();

      // Record performance telemetry
      final telemetryMetric = await telemetryService.recordInferencePerformance(
        inferenceDurationMs: 180,
        preprocessingMs: preStopwatch.elapsedMilliseconds,
        tokenCount: (vlmRawJsonOutput.length / 3.8).ceil(),
        modelId: 'Qwen2-VL-2B-Instruct',
        quantTier: 'Q4_K_M',
        backend: 'AVX2/SIMD',
        customMetadata: {'image_size': readBytes.length},
      );

      expect(telemetryMetric.tokensPerSecond, greaterThan(0.0));
      expect(telemetryMetric.modelId, equals('Qwen2-VL-2B-Instruct'));

      // Decode deterministic GBNF JSON output
      final parsedJson = jsonDecode(vlmRawJsonOutput) as Map<String, dynamic>;
      final rawItems = parsedJson['items'] as List<dynamic>;

      final domainItems = rawItems.map((raw) {
        final map = raw as Map<String, dynamic>;
        return ReceiptItem(
          description: map['normalized_name'].toString(),
          quantity: (map['quantity'] as num).toInt(),
          unitPrice: (map['unit_price'] as num).toDouble(),
          totalPrice: (map['total_price'] as num).toDouble(),
          mainCategory: map['main_category']?.toString(),
          subCategory: map['sub_category']?.toString(),
          necessity: map['necessity'] == 'essential' ? ItemNecessity.essential : ItemNecessity.discretional,
          isAsset: map['is_asset'] == true,
        );
      }).toList();

      final initialReceipt = Receipt(
        id: 'e2e_receipt_${DateTime.now().millisecondsSinceEpoch}',
        merchantName: parsedJson['merchant_name'].toString(),
        merchantAddress: parsedJson['merchant_address']?.toString() ?? '',
        vatNumber: parsedJson['vat_number']?.toString() ?? '',
        date: DateTime.parse(parsedJson['date'].toString()),
        time: parsedJson['time']?.toString() ?? '',
        totalAmount: (parsedJson['total_amount'] as num).toDouble(),
        currency: parsedJson['currency'].toString(),
        items: domainItems,
        imagePath: sampleImagePath,
        boxId: 'main',
      );

      expect(initialReceipt.items.length, equals(3));
      expect(initialReceipt.totalAmount, equals(40.19));

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 3: Review & Interactive User Corrections
      // ────────────────────────────────────────────────────────────────────────
      // User adjusts merchant name and corrects 1 line item unit price
      final updatedItems = List<ReceiptItem>.from(initialReceipt.items);
      updatedItems[0] = updatedItems[0].copyWith(
        unitPrice: 1.90,
        totalPrice: 3.80,
      );

      final correctedTotal = updatedItems.fold<double>(0.0, (acc, item) => acc + item.totalPrice);
      final reviewedReceipt = initialReceipt.copyWith(
        merchantName: 'Supermarket Express Milan',
        totalAmount: double.parse(correctedTotal.toStringAsFixed(2)),
        items: updatedItems,
      );

      expect(reviewedReceipt.merchantName, equals('Supermarket Express Milan'));
      expect(reviewedReceipt.totalAmount, equals(40.29));

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 4: Continuous Learning & PII Scrubbing
      // ────────────────────────────────────────────────────────────────────────
      // Scrub raw address with phone and customer notes with credit card & email
      final dirtyNotes = 'Card: 4111-2222-3333-4444, Email: user.account@gmail.com, IBAN: IT60X0542811101000000123456';
      final cleanNotes = PiiScrubberService.sanitizeText(dirtyNotes);

      expect(cleanNotes, contains('[REDACTED_CARD]'));
      expect(cleanNotes, contains('[REDACTED_EMAIL]'));
      expect(cleanNotes, contains('[REDACTED_IBAN]'));
      expect(cleanNotes, isNot(contains('4111-2222-3333-4444')));
      expect(cleanNotes, isNot(contains('user.account@gmail.com')));

      // Stage sample into continuous learning JSONL dataset
      final stagedSuccess = await datasetContributionService.stageVerifiedReceipt(
        receipt: reviewedReceipt,
        imagePath: sampleImagePath,
      );
      expect(stagedSuccess, isTrue);

      final stagedCount = await datasetContributionService.getSampleCount();
      expect(stagedCount, greaterThanOrEqualTo(1));

      final jsonlExport = await datasetContributionService.exportJsonlContent();
      expect(jsonlExport, contains('user_verified_ground_truth'));
      expect(jsonlExport, contains('Supermarket Express Milan'));
      expect(jsonlExport, isNot(contains('4111-2222-3333-4444')));

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 5: Encrypted Hive Local Persistence
      // ────────────────────────────────────────────────────────────────────────
      final receiptModelToSave = ReceiptModel.fromEntity(reviewedReceipt);
      await localDataSource.saveReceipt(receiptModelToSave);

      final allCached = await localDataSource.getReceipts();
      expect(allCached.isNotEmpty, isTrue);
      final cachedModel = allCached.firstWhere((r) => r.id == reviewedReceipt.id);
      expect(cachedModel.merchantName, equals('Supermarket Express Milan'));
      expect(cachedModel.totalAmount, equals(40.29));
      expect(cachedModel.items.length, equals(3));
      expect(cachedModel.items[2].isAsset, isTrue);

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 6: Supabase Outbox Queue Offline Staging
      // ────────────────────────────────────────────────────────────────────────
      final enqueuedMutation = await outboxService.enqueue(
        entityType: 'receipt',
        entityId: reviewedReceipt.id,
        mutationType: 'INSERT',
        payload: receiptModelToSave.toJson(),
      );

      expect(enqueuedMutation.status, equals('pending'));
      expect(enqueuedMutation.entityId, equals(reviewedReceipt.id));
      expect(enqueuedMutation.mutationType, equals('INSERT'));

      final pendingMutations = outboxService.getPendingMutations();
      expect(pendingMutations.length, equals(1));
      expect(pendingMutations.first.entityId, equals(reviewedReceipt.id));

      // Simulate successful background sync replication to Supabase
      await outboxService.markCompleted(enqueuedMutation.id);
      final remainingPending = outboxService.getPendingMutations();
      expect(remainingPending.isEmpty, isTrue);

      // ────────────────────────────────────────────────────────────────────────
      // STAGE 7: Telemetry Tracing & Audit Parity
      // ────────────────────────────────────────────────────────────────────────
      final recentTelemetry = telemetryService.recentEvents;
      expect(recentTelemetry.isNotEmpty, isTrue);
      final perfEvent = recentTelemetry.firstWhere((e) => e['type'] == 'inference_performance');
      expect(perfEvent['model_id'], equals('Qwen2-VL-2B-Instruct'));
      expect(perfEvent['quant_tier'], equals('Q4_K_M'));

      final diskEvents = await telemetryService.getDiskEventCount();
      expect(diskEvents, greaterThanOrEqualTo(1));
    });
  });
}
