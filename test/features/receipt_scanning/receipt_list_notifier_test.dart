import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartz/dartz.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

class MockReceiptRepository implements ReceiptRepository {
  List<Receipt> receipts = [];

  @override
  Future<Either<Failure, List<Receipt>>> getReceipts() async {
    return Right(receipts);
  }

  @override
  Future<Either<Failure, Receipt>> saveReceipt(Receipt receipt) async {
    receipts.removeWhere((r) => r.id == receipt.id);
    receipts.insert(0, receipt);
    return Right(receipt);
  }

  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    receipts.removeWhere((r) => r.id == id);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> clearAllData({bool includeCloud = false}) async {
    receipts.clear();
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockReceiptRepository mockRepo;
  late ReceiptListNotifier notifier;

  final sampleReceipt1 = Receipt(
    id: 'rcpt-1',
    merchantName: 'Supermarket',
    date: DateTime(2024, 5, 10),
    totalAmount: 45.50,
    currency: 'USD',
  );

  final sampleReceipt2 = Receipt(
    id: 'rcpt-2',
    merchantName: 'Bookstore',
    date: DateTime(2024, 5, 11),
    totalAmount: 18.00,
    currency: 'USD',
  );

  setUp(() {
    mockRepo = MockReceiptRepository();
    mockRepo.receipts = [sampleReceipt1];
    notifier = ReceiptListNotifier(mockRepo);
  });

  group('ReceiptListNotifier - Seamless State Transitions without Loading Flicker', () {
    test('initial state loads receipts and sets AsyncValue.data', () async {
      await notifier.loadReceipts();
      expect(notifier.state.hasValue, isTrue);
      expect(notifier.state.value!.length, 1);
      expect(notifier.state.value!.first.id, 'rcpt-1');
    });

    test('addReceipt updates state synchronously with AsyncValue.data without triggering loading state', () async {
      await notifier.loadReceipts();
      expect(notifier.state.hasValue, isTrue);

      final statesObserved = <AsyncValue<List<Receipt>>>[];
      notifier.addListener((state) {
        statesObserved.add(state);
      });

      await notifier.addReceipt(sampleReceipt2);

      // Verify that no AsyncLoading state was emitted during add
      final hadLoading = statesObserved.any((s) => s is AsyncLoading);
      expect(hadLoading, isFalse, reason: 'addReceipt should not emit AsyncLoading when state already has values');

      expect(notifier.state.value!.length, 2);
      expect(notifier.state.value!.first.id, 'rcpt-2');
    });

    test('deleteReceipt updates state synchronously without triggering loading state', () async {
      await notifier.loadReceipts();
      await notifier.addReceipt(sampleReceipt2);
      expect(notifier.state.value!.length, 2);

      final statesObserved = <AsyncValue<List<Receipt>>>[];
      notifier.addListener((state) {
        statesObserved.add(state);
      });

      await notifier.deleteReceipt('rcpt-1');

      final hadLoading = statesObserved.any((s) => s is AsyncLoading);
      expect(hadLoading, isFalse, reason: 'deleteReceipt should not emit AsyncLoading when state already has values');

      expect(notifier.state.value!.length, 1);
      expect(notifier.state.value!.first.id, 'rcpt-2');
    });

    test('subsequent loadReceipts does not flicker to loading if state already has data', () async {
      await notifier.loadReceipts();
      expect(notifier.state.hasValue, isTrue);

      final statesObserved = <AsyncValue<List<Receipt>>>[];
      notifier.addListener((state) {
        statesObserved.add(state);
      });

      await notifier.loadReceipts();

      final hadLoading = statesObserved.any((s) => s is AsyncLoading);
      expect(hadLoading, isFalse, reason: 'loadReceipts should not flicker to AsyncLoading if data already exists');
    });
  });
}
