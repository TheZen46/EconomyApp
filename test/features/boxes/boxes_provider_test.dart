import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/sync/models/sync_outbox_item.dart';
import 'package:t_aidy/core/sync/sync_providers.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

void main() {
  group('BoxesNotifier - Active Box Deletion Handling', () {
    test('resets activeBoxId to main when the active custom box is deleted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);

      // Create a custom box
      final customBox = await notifier.createNew(
        name: 'Travel 2024',
        budget: 1500,
        currency: 'USD',
        color: Colors.blue,
      );

      // Set active box to the custom box
      container.read(activeBoxIdProvider.notifier).state = customBox.id;
      expect(container.read(activeBoxIdProvider), customBox.id);

      // Delete the active custom box
      await notifier.deleteBox(customBox.id);

      // Verify active box falls back immediately to 'main'
      expect(container.read(activeBoxIdProvider), 'main');
      expect(container.read(boxesProvider).any((b) => b.id == customBox.id), isFalse);
    });

    test('retains activeBoxId if a different non-active box is deleted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);

      final boxA = await notifier.createNew(
        name: 'Groceries',
        budget: 400,
        currency: 'USD',
        color: Colors.green,
      );
      final boxB = await notifier.createNew(
        name: 'Tech Setup',
        budget: 800,
        currency: 'USD',
        color: Colors.purple,
      );

      // Set active box to boxA
      container.read(activeBoxIdProvider.notifier).state = boxA.id;

      // Delete boxB
      await notifier.deleteBox(boxB.id);

      // Verify active box remains boxA
      expect(container.read(activeBoxIdProvider), boxA.id);
    });
  });

  group('BoxesNotifier - receipts of a deleted box', () {
    late Directory tempDir;

    setUpAll(() {
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ReceiptItemModelAdapter());
      if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SyncOutboxItemAdapter());
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('boxes_delete_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('are moved to the main box and queued for synchronization', () async {
      final receipts = await Hive.openBox<ReceiptModel>('receipts');
      final outbox = await Hive.openBox<SyncOutboxItem>('outbox');
      final container = ProviderContainer(overrides: [
        hiveBoxProvider.overrideWithValue(receipts),
        outboxHiveBoxProvider.overrideWithValue(outbox),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);
      final travel = await notifier.createNew(name: 'Travel', budget: 100, currency: 'EUR', color: Colors.blue);

      ReceiptModel receipt(String id, String boxId, {String itemBox = 'main'}) => ReceiptModel(
            id: id,
            merchantName: 'Shop',
            date: DateTime.utc(2026, 9, 1),
            totalAmount: 10,
            currency: 'EUR',
            boxId: boxId,
            items: [ReceiptItemModel(description: 'Item', unitPrice: 10, quantity: 1, boxId: itemBox)],
          );
      await receipts.put('in-travel', receipt('in-travel', travel.id, itemBox: travel.id));
      await receipts.put('item-only', receipt('item-only', 'main', itemBox: travel.id));
      await receipts.put('untouched', receipt('untouched', 'main'));
      await outbox.clear();

      await notifier.deleteBox(travel.id);

      final moved = receipts.get('in-travel')!;
      expect(moved.boxId, 'main');
      expect(moved.items.single.boxId, 'main');
      expect(moved.version, 2);
      expect(receipts.get('item-only')!.items.single.boxId, 'main');
      expect(receipts.get('untouched')!.version, 1);

      final queued = outbox.values.map((e) => '${e.entityType}:${e.entityId}:${e.mutationType}').toList();
      expect(queued, containsAll(['receipt:in-travel:upsert', 'receipt:item-only:upsert', 'box:${travel.id}:delete']));
      expect(queued, isNot(contains('receipt:untouched:upsert')));
    });
  });
}
