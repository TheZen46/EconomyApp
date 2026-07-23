import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/home_page.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/model_update_provider.dart';

void main() {
  testWidgets('Search bar interactions work as expected', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptListProvider.overrideWith((ref) => FakeReceiptListNotifier()),
          modelUpdateServiceProvider.overrideWith((ref) => FakeModelUpdateService()),
        ],
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    // Verify initial state
    expect(find.text('tAIdy'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('Everything'), findsNothing);

    // Tap search icon
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify expanded state
    expect(find.text('tAIdy'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Merchants'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Vault Assets'), findsOneWidget);

    // Tap close
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify restored state
    expect(find.text('tAIdy'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });
}

class FakeReceiptListNotifier extends ReceiptListNotifier {
  FakeReceiptListNotifier() : super(FakeReceiptRepository());

  @override
  Future<void> loadReceipts() async {
    state = const AsyncValue.data([]);
  }
}

class FakeReceiptRepository implements ReceiptRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeModelUpdateService extends ModelUpdateService {
  FakeModelUpdateService() : super(FakeModelRepository());
}

class FakeModelRepository implements ModelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
