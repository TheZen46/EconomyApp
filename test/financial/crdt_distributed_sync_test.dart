import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/crdt/crdt_sync_engine.dart';
import 'package:t_aidy/core/crdt/hlc.dart';
import 'package:t_aidy/core/crdt/lww_register.dart';
import 'package:t_aidy/core/crdt/receipt_crdt.dart';
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

    test('TAIDY-M19 Issue #41 (1): Line items have stable identity and middle deletion does not shift indices', () {
      final item1Id = 'item_uuid_1';
      final item2Id = 'item_uuid_2';
      final item3Id = 'item_uuid_3';

      final initialReceipt = ReceiptModel(
        id: 'rec_uuid_test',
        merchantName: 'Multi-Item Grocery',
        date: DateTime.utc(2026, 9, 10),
        totalAmount: 30.00,
        currency: 'EUR',
        items: [
          ReceiptItemModel(id: item1Id, description: 'Apples', unitPrice: 10.00, quantity: 1),
          ReceiptItemModel(id: item2Id, description: 'Bananas', unitPrice: 10.00, quantity: 1),
          ReceiptItemModel(id: item3Id, description: 'Cherries', unitPrice: 10.00, quantity: 1),
        ],
      );

      deviceA.recordReceipt(initialReceipt);
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      // Device A deletes the middle item (Bananas)
      deviceA.updateLineItem(
        receiptId: 'rec_uuid_test',
        itemId: item2Id,
        isDeleted: true,
      );

      // Device B edits Cherries (item 3)
      deviceB.updateLineItem(
        receiptId: 'rec_uuid_test',
        itemId: item3Id,
        unitPriceCents: 1500, // €15.00
      );

      // Exchange deltas
      deviceA.mergeDeltaPayload(deviceB.generateDeltaPayload());
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      final rA = deviceA.getReceipt('rec_uuid_test')!;
      final rB = deviceB.getReceipt('rec_uuid_test')!;

      // Both replicas must only have Apples and Cherries; Bananas must not reappear
      expect(rA.items.length, equals(2));
      expect(rB.items.length, equals(2));

      expect(rA.items.map((i) => i.description), containsAllInOrder(['Apples', 'Cherries']));
      expect(rB.items.map((i) => i.description), containsAllInOrder(['Apples', 'Cherries']));

      // Cherries price must be €15 on both
      expect(rA.items.firstWhere((i) => i.description == 'Cherries').unitPrice, equals(15.00));
      expect(rB.items.firstWhere((i) => i.description == 'Cherries').unitPrice, equals(15.00));
    });

    test('TAIDY-M19 Issue #41 (2): Derived totals correctly compute sum of active items during concurrent edits', () {
      final item1Id = 'item_conc_1';
      final item2Id = 'item_conc_2';

      final initialReceipt = ReceiptModel(
        id: 'rec_totals_test',
        merchantName: 'Supermarket',
        date: DateTime.utc(2026, 9, 10),
        totalAmount: 20.00,
        currency: 'EUR',
        items: [
          ReceiptItemModel(id: item1Id, description: 'Milk', unitPrice: 10.00, quantity: 1),
          ReceiptItemModel(id: item2Id, description: 'Bread', unitPrice: 10.00, quantity: 1),
        ],
      );

      deviceA.recordReceipt(initialReceipt);
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      // Device A edits Milk: 10 -> 12 EUR
      deviceA.updateLineItem(
        receiptId: 'rec_totals_test',
        itemId: item1Id,
        unitPriceCents: 1200,
      );

      // Device B concurrently edits Bread: 10 -> 15 EUR
      deviceB.updateLineItem(
        receiptId: 'rec_totals_test',
        itemId: item2Id,
        unitPriceCents: 1500,
      );

      // Merge both ways
      deviceA.mergeDeltaPayload(deviceB.generateDeltaPayload());
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      final rA = deviceA.getReceipt('rec_totals_test')!;
      final rB = deviceB.getReceipt('rec_totals_test')!;

      // Total must be 12 + 15 = 27 EUR on both replicas, not whichever LWW total won
      expect(rA.totalAmount, equals(27.00));
      expect(rB.totalAmount, equals(27.00));
    });

    test('TAIDY-M19 Issue #41 (3): Local HLC advances to maximum observed register HLC preventing regression', () {
      final highHlc = Hlc(millis: 500000, counter: 42, nodeId: 'high_node');
      final remoteReceipt = ReceiptCrdt(
        id: 'future_receipt',
        merchantName: LwwRegister('Future Store', highHlc),
        totalAmountCents: LwwRegister(1000, highHlc),
        currency: LwwRegister('EUR', highHlc),
        receiptDateMillis: LwwRegister(10000, highHlc),
        vatNumber: LwwRegister('', highHlc),
        merchantAddress: LwwRegister('', highHlc),
        boxId: LwwRegister('main', highHlc),
        isDeleted: LwwRegister(false, highHlc),
        items: {},
      );

      final payload = SyncDeltaPayload(
        senderNodeId: 'high_node',
        generatedAtMillis: 1000, // payload generatedAtMillis is low
        vectorClock: VectorClock({'high_node': 1}),
        modifiedReceipts: [remoteReceipt],
      );

      // Merge into device A (which had local HLC around 1000)
      deviceA.mergeDeltaPayload(payload);

      // Device A's HLC must now be >= 500000
      expect(deviceA.currentHlc.millis, greaterThanOrEqualTo(500000));

      // A new local mutation on device A must receive an HLC causally after the merged remote state
      final localReceipt = deviceA.recordReceipt(
        ReceiptModel(
          id: 'next_local',
          merchantName: 'Local Store',
          date: DateTime.utc(2026, 9, 10),
          totalAmount: 5.0,
          currency: 'EUR',
          items: [],
        ),
      );

      expect(localReceipt.merchantName.hlc.isAfter(highHlc), isTrue);
    });

    test('TAIDY-M19 Issue #41 (4): Tombstones require causal stability before pruning to avoid resurrection', () {
      // Register deviceB as a known replica of deviceA
      deviceA.registerPeer('device_b');

      final r = ReceiptModel(
        id: 'rec_causal_prune',
        merchantName: 'Doomed Store',
        date: DateTime.utc(2026, 9, 10),
        totalAmount: 10.0,
        currency: 'EUR',
        items: [],
      );

      deviceA.recordReceipt(r);
      // Sync initial state to B
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());

      // Device A deletes the receipt
      deviceA.deleteReceipt('rec_causal_prune');

      // Attempt pruning with cutoff in the future:
      // Device B has NOT acknowledged the deletion yet, so it must NOT prune!
      final prunedEarly = deviceA.pruneTombstones(DateTime.now().toUtc().millisecondsSinceEpoch + 100000);
      expect(prunedEarly, equals(0));
      expect(deviceA.getReceipt('rec_causal_prune', includeDeleted: true), isNotNull);

      // Now Device B syncs and receives the deletion from Device A
      deviceB.mergeDeltaPayload(deviceA.generateDeltaPayload());
      // Device B sends its sync acknowledgment delta back to Device A
      deviceA.mergeDeltaPayload(deviceB.generateDeltaPayload());

      // Now that Device B is causally stable, pruning must succeed!
      final prunedLate = deviceA.pruneTombstones(DateTime.now().toUtc().millisecondsSinceEpoch + 100000);
      expect(prunedLate, equals(1));
      expect(deviceA.getReceipt('rec_causal_prune', includeDeleted: true), isNull);
    });

    test('TAIDY-M19 Issue #41 (5): Engine state persists to and restores from CrdtStorage', () async {
      final storage = InMemoryCrdtStorage();
      final engine = CrdtSyncEngine(nodeId: 'persistent_node', storage: storage);

      engine.recordReceipt(
        ReceiptModel(
          id: 'persisted_rec',
          merchantName: 'Persisted Merchant',
          date: DateTime.utc(2026, 9, 10),
          totalAmount: 42.00,
          currency: 'EUR',
          items: [
            ReceiptItemModel(
              id: 'persisted_item',
              description: 'Persisted Widget',
              unitPrice: 42.00,
              quantity: 1,
            ),
          ],
        ),
      );

      await engine.persist();

      // Restore a brand new engine from the same storage
      final restoredEngine = await CrdtSyncEngine.createWithStorage(
        nodeId: 'persistent_node',
        storage: storage,
      );

      expect(restoredEngine.count, equals(1));
      final receipt = restoredEngine.getReceipt('persisted_rec')!;
      expect(receipt.merchantName, equals('Persisted Merchant'));
      expect(receipt.totalAmount, equals(42.00));
      expect(receipt.items.first.description, equals('Persisted Widget'));
      expect(restoredEngine.currentHlc, equals(engine.currentHlc));
      expect(restoredEngine.currentVectorClock, equals(engine.currentVectorClock));
    });
  });
}
