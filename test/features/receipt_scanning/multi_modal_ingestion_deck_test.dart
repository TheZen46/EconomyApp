import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/multi_modal_ingestion_deck.dart';

class MockBoxesNotifier extends StateNotifier<List<BoxModel>> implements BoxesNotifier {
  MockBoxesNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  MockReceiptListNotifier(super.state);

  Receipt? addedReceipt;

  @override
  Future<void> addReceipt(Receipt receipt) async {
    addedReceipt = receipt;
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, receipt]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('MultiModalIngestionDeck renders dual pane and checks parity verification', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final testBoxes = [
      BoxModel(id: 'box_biz', name: 'LLC Consulting Box', budget: 10000, spent: 2500, currency: 'USD', color: 0),
    ];

    final receiptNotifier = MockReceiptListNotifier(const AsyncValue.data([]));
    bool completed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boxesProvider.overrideWith((ref) => MockBoxesNotifier(testBoxes)),
          receiptListProvider.overrideWith((ref) => receiptNotifier),
        ],
        child: MaterialApp(
          home: MultiModalIngestionDeck(
            onComplete: () {
              completed = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify initial render
    expect(find.text('Camera OCR'), findsOneWidget);
    expect(find.text('Voice Dictate'), findsOneWidget);
    expect(find.text('Manual Matrix'), findsOneWidget);
    expect(find.text('LOCAL VLM OCR ACTIVE'), findsOneWidget);
    expect(find.text('Confirm & Shield Tax'), findsOneWidget);

    // Initial default seed is: items (20 + 15) + tax (3.50) + tip (7.00) = 45.50 -> Parity verified
    expect(find.text('PARITY VERIFIED'), findsOneWidget);

    // Enter a mismatching grand total to trigger parity discrepancy warning
    final totalField = find.widgetWithText(TextField, '45.50');
    expect(totalField, findsOneWidget);
    await tester.enterText(totalField, '99.00');
    await tester.pumpAndSettle();

    expect(find.text('PARITY DISCREPANCY'), findsOneWidget);
    expect(find.text('Auto-Correct Total'), findsOneWidget);

    // Tap Auto-Correct Total
    await tester.tap(find.text('Auto-Correct Total'));
    await tester.pumpAndSettle();

    expect(find.text('PARITY VERIFIED'), findsOneWidget);
    expect(find.text('45.50'), findsOneWidget);

    // Switch to Voice Dictate mode
    await tester.tap(find.text('Voice Dictate'));
    await tester.pumpAndSettle();

    expect(find.text('On-Device Speech Transcription Stream'), findsOneWidget);

    // Confirm & Shield Tax
    await tester.tap(find.text('Confirm & Shield Tax'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(receiptNotifier.addedReceipt, isNotNull);
    expect(receiptNotifier.addedReceipt!.merchantName, contains('Olive Garden'));
  });
}
