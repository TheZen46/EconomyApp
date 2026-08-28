import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartz/dartz.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
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
    receipts.add(receipt);
    return Right(receipt);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('filteredReceiptsByActiveBoxProvider Tests', () {
    late MockReceiptRepository mockRepo;
    late Receipt mainReceipt;
    late Receipt travelReceipt;
    late Receipt businessReceipt;

    setUp(() {
      mainReceipt = Receipt(
        id: 'rcpt-main',
        merchantName: 'Grocery Store',
        date: DateTime(2024, 7, 1),
        totalAmount: 50.0,
        currency: 'USD',
        boxId: 'main',
      );

      travelReceipt = Receipt(
        id: 'rcpt-travel',
        merchantName: 'Airline Tickets',
        date: DateTime(2024, 7, 5),
        totalAmount: 350.0,
        currency: 'USD',
        boxId: 'travel-box-123',
      );

      businessReceipt = Receipt(
        id: 'rcpt-biz',
        merchantName: 'Coworking Space',
        date: DateTime(2024, 7, 10),
        totalAmount: 120.0,
        currency: 'USD',
        boxId: 'business-box-456',
      );

      mockRepo = MockReceiptRepository();
      mockRepo.receipts = [mainReceipt, travelReceipt, businessReceipt];
    });

    test('returns only main box receipts when activeBoxId is "main"', () async {
      final container = ProviderContainer(
        overrides: [
          receiptRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      // Verify active box defaults to 'main'
      expect(container.read(activeBoxIdProvider), 'main');

      // Trigger load
      await container.read(receiptListProvider.notifier).loadReceipts();

      final filtered = container.read(filteredReceiptsByActiveBoxProvider);
      expect(filtered.hasValue, isTrue);
      final list = filtered.value!;
      expect(list.length, 1);
      expect(list.first.id, 'rcpt-main');
    });

    test('re-aggregates receipts dynamically when activeBoxId changes', () async {
      final container = ProviderContainer(
        overrides: [
          receiptRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(receiptListProvider.notifier).loadReceipts();

      // Switch to travel box
      container.read(activeBoxIdProvider.notifier).state = 'travel-box-123';

      final travelFiltered = container.read(filteredReceiptsByActiveBoxProvider);
      expect(travelFiltered.value!.length, 1);
      expect(travelFiltered.value!.first.id, 'rcpt-travel');

      // Switch to business box
      container.read(activeBoxIdProvider.notifier).state = 'business-box-456';

      final bizFiltered = container.read(filteredReceiptsByActiveBoxProvider);
      expect(bizFiltered.value!.length, 1);
      expect(bizFiltered.value!.first.id, 'rcpt-biz');

      // Switch back to main
      container.read(activeBoxIdProvider.notifier).state = 'main';
      final mainFiltered = container.read(filteredReceiptsByActiveBoxProvider);
      expect(mainFiltered.value!.length, 1);
      expect(mainFiltered.value!.first.id, 'rcpt-main');
    });

    test('handles receipts with null boxId by defaulting them to main', () async {
      final legacyReceipt = Receipt(
        id: 'rcpt-legacy',
        merchantName: 'Old Corner Store',
        date: DateTime(2024, 1, 1),
        totalAmount: 15.0,
        currency: 'USD',
        boxId: null,
      );

      mockRepo.receipts.add(legacyReceipt);

      final container = ProviderContainer(
        overrides: [
          receiptRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(receiptListProvider.notifier).loadReceipts();

      final filtered = container.read(filteredReceiptsByActiveBoxProvider);
      final list = filtered.value!;
      expect(list.any((r) => r.id == 'rcpt-legacy'), isTrue);
    });
  });
}
