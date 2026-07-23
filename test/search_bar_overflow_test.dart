import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/home_page.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:dartz/dartz.dart';

class MockReceiptRepository implements ReceiptRepository {
  @override
  Future<Either<Failure, List<Receipt>>> getReceipts() async {
    return const Right([]);
  }
  
  @override
  Future<Either<Failure, Receipt>> saveReceipt(Receipt receipt) async {
    return Right(receipt);
  }
  
  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    return const Right(null);
  }
  
  @override
  Future<Either<Failure, void>> clearAllData({bool includeCloud = false}) async {
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockModelRepository implements ModelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Search bar expansion does not overflow', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      throw details.exception;
    };

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptRepositoryProvider.overrideWithValue(MockReceiptRepository()),
          modelRepositoryProvider.overrideWithValue(MockModelRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: HomePage(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));

    final searchIcon = find.byIcon(Icons.search);
    expect(searchIcon, findsOneWidget);
    await tester.tap(searchIcon);
    await tester.pump(const Duration(seconds: 1));

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
