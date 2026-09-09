import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/crdt/crdt_sync_engine.dart';
import 'package:t_aidy/core/crdt/hlc.dart';
import 'package:t_aidy/core/crdt/lww_register.dart';
import 'package:t_aidy/core/crdt/vector_clock.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

void main() {
  group('HLC & VectorClock Causality Tests', () {
    test('HLC establishes strict total order with node ID tie breaking', () {
      final h1 = Hlc(millis: 100, counter: 0, nodeId: 'device_a');
      final h2 = Hlc(millis: 100, counter: 1, nodeId: 'device_a');
      final h3 = Hlc(millis: 100, counter: 1, nodeId: 'device_b');
      final h4 = Hlc(millis: 105, counter: 0, nodeId: 'device_a');

      expect(h1.compareTo(h2), lessThan(0));
      expect(h2.compareTo(h3), lessThan(0)); // 'device_a' < 'device_b'
      expect(h3.compareTo(h4), lessThan(0));
    });

    test('VectorClock accurately detects causal ancestry and concurrency', () {
      final v1 = VectorClock({'A': 1, 'B': 1});
      final v2 = VectorClock({'A': 2, 'B': 1}); // v2 is descendant of v1
      final v3 = VectorClock({'A': 1, 'B': 2}); // v3 is concurrent with v2

      expect(v2.isDescendantOf(v1), isTrue);
      expect(v1.isDescendantOf(v2), isFalse);
      expect(v2.isConcurrentWith(v3), isTrue);

      final merged = v2.merge(v3);
      expect(merged.entries, equals({'A': 2, 'B': 2}));
    });
  });

  group('LwwRegister Algebraic Join-Semilattice Proofs', () {
    test('satisfies Idempotence (x ⊔ x == x)', () {
      final h = Hlc(millis: 100, counter: 0, nodeId: 'A');
      final reg = LwwRegister('value_1', h);
      expect(reg.merge(reg), equals(reg));
    });

    test('satisfies Commutativity (x ⊔ y == y ⊔ x)', () {
      final h1 = Hlc(millis: 100, counter: 0, nodeId: 'A');
      final h2 = Hlc(millis: 105, counter: 0, nodeId: 'B');
      final reg1 = LwwRegister('old_val', h1);
      final reg2 = LwwRegister('new_val', h2);

      final merge12 = reg1.merge(reg2);
      final merge21 = reg2.merge(reg1);
      expect(merge12, equals(merge21));
      expect(merge12.value, equals('new_val'));
    });

    test('satisfies Associativity ((x ⊔ y) ⊔ z == x ⊔ (y ⊔ z))', () {
      final h1 = Hlc(millis: 100, counter: 0, nodeId: 'A');
      final h2 = Hlc(millis: 105, counter: 0, nodeId: 'B');
      final h3 = Hlc(millis: 110, counter: 0, nodeId: 'C');
      final reg1 = LwwRegister('val_a', h1);
      final reg2 = LwwRegister('val_b', h2);
      final reg3 = LwwRegister('val_c', h3);

      final left = (reg1.merge(reg2)).merge(reg3);
      final right = reg1.merge(reg2.merge(reg3));
      expect(left, equals(right));
      expect(left.value, equals('val_c'));
    });
  });

  group('CrdtSyncEngine Multi-Device Offline Sync Scenarios', () {
    late CrdtSyncEngine deviceA;
    late CrdtSyncEngine deviceB;

    setUp(() {
      deviceA = CrdtSyncEngine(
        nodeId: 'device_a',
        initialHlc: Hlc(millis: 1000, counter: 0, nodeId: 'device_a'),
      );
      deviceB = CrdtSyncEngine(
        nodeId: 'device_b',
        initialHlc: Hlc(millis: 1000, counter: 0, nodeId: 'device_b'),
      );
    });

    test('Scenario 1: Orthogonal field edits on same line item merge without data loss', () {
      // 1. Device A creates receipt
      final initialReceipt = ReceiptModel(
        id: 'rec_001',
        merchantName: 'Esselunga Milano',
        date: DateTime.utc(2026, 9, 9),
        totalAmount: 10.00,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            description: 'Barilla Pasta 500g',
            unitPrice: 10.00,
            quantity: 1,
            category: 'Pantry',
          ),
        ],
      );

      deviceA.recordReceipt(initialReceipt);

      // Sync initial state from A to B
      final initialDelta = deviceA.generateDeltaPayload();
      deviceB.mergeDeltaPayload(initialDelta);

      // 2. Both devices go offline
      // Device A edits price: 10.00 -> 12.00 EUR (1200 cents)
      deviceA.updateLineItem(
        receiptId: 'rec_001',
        itemId: 'rec_001_item_0',
        unitPriceCents: 1200,
      );

      // Device B edits category: 'Pantry' -> 'Grains & Pasta'
      deviceB.updateLineItem(
        receiptId: 'rec_001',
        itemId: 'rec_001_item_0',
        category: 'Grains & Pasta',
      );

      // 3. Devices reconnect and exchange sync deltas
      final deltaA = deviceA.generateDeltaPayload();
      final deltaB = deviceB.generateDeltaPayload();

      deviceA.mergeDeltaPayload(deltaB);
      deviceB.mergeDeltaPayload(deltaA);

      // 4. Verify identical merged state on both devices
      final resultA = deviceA.getReceipt('rec_001')!;
      final resultB = deviceB.getReceipt('rec_001')!;

      expect(resultA.items.first.unitPrice, equals(12.00));
      expect(resultA.items.first.category, equals('Grains & Pasta'));

      expect(resultB.items.first.unitPrice, equals(12.00));
      expect(resultB.items.first.category, equals('Grains & Pasta'));
      expect(resultA.totalAmount, equals(resultB.totalAmount));
    });

    test('Scenario 2: Colliding field edits resolve deterministically via HLC total order', () {
      final initialReceipt = ReceiptModel(
        id: 'rec_002',
        merchantName: 'Apple Store',
        date: DateTime.utc(2026, 9, 9),
        totalAmount: 100.00,
        currency: 'EUR',
        items: [
          ReceiptItemModel(
            description: 'USB-C Cable',
            unitPrice: 20.00,
            quantity: 5,
          ),
        ],
      );

      deviceA.recordReceipt(initialReceipt);
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      // Device A edits description to "USB-C Charge Cable 1m"
      deviceA.updateLineItem(
        receiptId: 'rec_002',
        itemId: 'rec_002_item_0',
        description: 'USB-C Charge Cable 1m',
      );

      // Device B edits description to "USB-C High-Speed Cable 2m" (Device B has lexicographically higher nodeId)
      deviceB.updateLineItem(
        receiptId: 'rec_002',
        itemId: 'rec_002_item_0',
        description: 'USB-C High-Speed Cable 2m',
      );

      // Exchange deltas
      deviceA.mergeDeltaPayload(deviceB.generateDeltaPayload());
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      final rA = deviceA.getReceipt('rec_002')!;
      final rB = deviceB.getReceipt('rec_002')!;

      // Both must converge to the exact same string
      expect(rA.items.first.description, equals(rB.items.first.description));
    });

    test('Scenario 3: Delete vs Edit resolves causally (resurrection on causal edit)', () {
      final initialReceipt = ReceiptModel(
        id: 'rec_003',
        merchantName: 'Target USA',
        date: DateTime.utc(2026, 9, 9),
        totalAmount: 50.00,
        currency: 'USD',
        items: [
          ReceiptItemModel(description: 'Desk Lamp', unitPrice: 50.00, quantity: 1),
        ],
      );

      deviceA.recordReceipt(initialReceipt);
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      // Device A deletes line item
      deviceA.updateLineItem(
        receiptId: 'rec_003',
        itemId: 'rec_003_item_0',
        isDeleted: true,
      );

      // Device B edits line item after learning of delete or with higher clock
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());
      deviceB.updateLineItem(
        receiptId: 'rec_003',
        itemId: 'rec_003_item_0',
        description: 'Deluxe LED Desk Lamp',
        isDeleted: false,
      );

      // Merge back to Device A
      deviceA.mergeDeltaPayload(deviceB.generateDeltaPayload());

      final resA = deviceA.getReceipt('rec_003')!;
      expect(resA.items, isNotEmpty);
      expect(resA.items.first.description, equals('Deluxe LED Desk Lamp'));
    });

    test('Scenario 4: Tombstone pruning purges old deletions cleanly', () {
      final r1 = ReceiptModel(
        id: 'rec_prune_1',
        merchantName: 'Old Store',
        date: DateTime.utc(2026, 1, 1),
        totalAmount: 15.00,
        currency: 'EUR',
        items: [],
      );

      deviceA.recordReceipt(r1);
      deviceA.deleteReceipt('rec_prune_1');

      expect(deviceA.getReceipt('rec_prune_1'), isNull);
      expect(deviceA.getReceipt('rec_prune_1', includeDeleted: true), isNotNull);

      // Prune tombstones older than now + 1000ms
      deviceA.pruneTombstones(DateTime.now().toUtc().millisecondsSinceEpoch + 5000);

      expect(deviceA.getReceipt('rec_prune_1', includeDeleted: true), isNull);
    });
  });
}
