import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box<SyncOutboxItem> outboxBox;
  late OutboxService outboxService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('outbox_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(SyncOutboxItemAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    outboxBox = await Hive.openBox<SyncOutboxItem>('test_outbox_${DateTime.now().millisecondsSinceEpoch}');
    outboxService = OutboxService(outboxBox);
  });

  tearDown(() async {
    await outboxBox.deleteFromDisk();
  });

  group('OutboxService Unit Tests', () {
    test('enqueues mutations and preserves ordering', () async {
      final item1 = await outboxService.enqueue(
        entityType: 'receipt',
        entityId: 'rec-001',
        mutationType: 'insert',
        payload: {'merchant_name': 'Cafe Nero', 'total_amount': 4.50},
      );

      final item2 = await outboxService.enqueue(
        entityType: 'invoice',
        entityId: 'inv-001',
        mutationType: 'update',
        payload: {'client_name': 'Acme Corp', 'amount': 1200.0},
      );

      final pending = outboxService.getPendingMutations();
      expect(pending.length, 2);
      expect(pending[0].id, item1.id);
      expect(pending[0].entityType, 'receipt');
      expect(pending[1].id, item2.id);
      expect(pending[1].entityType, 'invoice');
    });

    test('markCompleted removes mutation from outbox', () async {
      final item = await outboxService.enqueue(
        entityType: 'box',
        entityId: 'box-001',
        mutationType: 'insert',
        payload: {'name': 'Freelance'},
      );

      expect(outboxService.getPendingMutations().length, 1);
      await outboxService.markCompleted(item.id);
      expect(outboxService.getPendingMutations().isEmpty, true);
    });

    test('markFailed increments retryCount and transitions to permanently_failed after 5 attempts', () async {
      final item = await outboxService.enqueue(
        entityType: 'asset',
        entityId: 'asset-001',
        mutationType: 'delete',
        payload: {},
      );

      for (int i = 1; i <= 4; i++) {
        await outboxService.markFailed(item.id, 'Timeout error');
        final current = outboxBox.get(item.id)!;
        expect(current.retryCount, i);
        expect(current.status, 'failed');
      }

      await outboxService.markFailed(item.id, 'Fatal error');
      final failedItem = outboxBox.get(item.id)!;
      expect(failedItem.retryCount, 5);
      expect(failedItem.status, 'permanently_failed');
    });
  });
}
