import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/sync/sync_coordinator.dart';
import 'package:t_aidy/core/crdt/hlc.dart';
import 'package:t_aidy/core/crdt/receipt_crdt.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

void main() {
  group('SyncCoordinator Tests', () {
    test('guarantees mutual exclusion and serial execution across concurrent callers', () async {
      final coordinator = SyncCoordinator.instance;
      final order = <int>[];

      final future1 = coordinator.synchronized(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        order.add(1);
        return 1;
      });

      final future2 = coordinator.synchronized(() async {
        await Future.delayed(const Duration(milliseconds: 10));
        order.add(2);
        return 2;
      });

      final future3 = coordinator.synchronized(() async {
        order.add(3);
        return 3;
      });

      final results = await Future.wait([future1, future2, future3]);

      expect(results, equals([1, 2, 3]));
      expect(order, equals([1, 2, 3]));
    });

    test('ReceiptCrdt merges divergent remote and local receipt fields deterministically', () {
      final baseDate = DateTime.utc(2026, 1, 1);
      final localModel = ReceiptModel(
        id: 'rcpt-merge-1',
        merchantName: 'Local Merchant Name',
        date: baseDate,
        totalAmount: 50.0,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            id: 'item-1',
            description: 'Item 1',
            unitPrice: 20.0,
            quantity: 1,
            totalPrice: 20.0,
          ),
          ReceiptItemModel(
            id: 'item-local-only',
            description: 'Local Item',
            unitPrice: 30.0,
            quantity: 1,
            totalPrice: 30.0,
          ),
        ],
        updatedAt: DateTime.utc(2026, 1, 2),
        version: 2,
      );

      final remoteModel = ReceiptModel(
        id: 'rcpt-merge-1',
        merchantName: 'Remote Merchant Name',
        date: baseDate,
        totalAmount: 60.0,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            id: 'item-1',
            description: 'Item 1 Updated Remotely',
            unitPrice: 25.0,
            quantity: 1,
            totalPrice: 25.0,
          ),
          ReceiptItemModel(
            id: 'item-remote-only',
            description: 'Remote Item',
            unitPrice: 35.0,
            quantity: 1,
            totalPrice: 35.0,
          ),
        ],
        updatedAt: DateTime.utc(2026, 1, 3),
        version: 3,
      );

      final localHlc = Hlc(
        millis: localModel.updatedAt!.millisecondsSinceEpoch,
        counter: localModel.version,
        nodeId: 'local',
      );
      final remoteHlc = Hlc(
        millis: remoteModel.updatedAt!.millisecondsSinceEpoch,
        counter: remoteModel.version,
        nodeId: 'remote',
      );

      final localCrdt = ReceiptCrdt.fromModel(localModel, localHlc);
      final remoteCrdt = ReceiptCrdt.fromModel(remoteModel, remoteHlc);
      final mergedCrdt = localCrdt.merge(remoteCrdt);
      final mergedModel = mergedCrdt.toModel();

      // Remote merchant name wins because remote HLC has higher timestamp/version
      expect(mergedModel.merchantName, equals('Remote Merchant Name'));

      // Both items are present in merged result
      final itemIds = mergedModel.items.map((i) => i.id).toSet();
      expect(itemIds.contains('item-1'), isTrue);
      expect(itemIds.contains('item-local-only'), isTrue);
      expect(itemIds.contains('item-remote-only'), isTrue);

      // item-1 has remote description and price
      final mergedItem1 = mergedModel.items.firstWhere((i) => i.id == 'item-1');
      expect(mergedItem1.description, equals('Item 1 Updated Remotely'));
      expect(mergedItem1.unitPrice, equals(25.0));
    });
  });
}
