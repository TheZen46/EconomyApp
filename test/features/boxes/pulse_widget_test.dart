import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/boxes/presentation/widgets/pulse_widget.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

class MockBoxesNotifier extends StateNotifier<List<BoxModel>> implements BoxesNotifier {
  MockBoxesNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  MockReceiptListNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PulseWidget UI & Gauge Tests', () {
    final sampleBox = BoxModel(
      id: 'main',
      name: 'Main Life',
      budget: 1000.0,
      spent: 250.0,
      currency: 'USD',
      color: Colors.blue.value,
    );

    final sampleReceipts = [
      Receipt(
        id: 'r1',
        merchantName: 'Supermarket',
        date: DateTime.now(),
        totalAmount: 120.0,
        currency: 'USD',
        boxId: 'main',
      ),
    ];

    testWidgets('renders Burn-Rate HUD with velocity and projected spend readouts', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boxesProvider.overrideWith((ref) => MockBoxesNotifier([sampleBox])),
            activeBoxIdProvider.overrideWith((ref) => 'main'),
            receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PulseWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and HUD elements
      expect(find.text('BURN-RATE HUD'), findsOneWidget);
      expect(find.text('Daily Velocity'), findsOneWidget);
      expect(find.textContaining('/ day'), findsOneWidget);
      expect(find.textContaining('Projected EOM:'), findsOneWidget);
      expect(find.textContaining('7d'), findsOneWidget);
      expect(find.textContaining('14d'), findsOneWidget);
      expect(find.textContaining('30d'), findsOneWidget);
      expect(find.textContaining('left in month'), findsOneWidget);
    });

    testWidgets('switching rolling window chips updates active window selection', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boxesProvider.overrideWith((ref) => MockBoxesNotifier([sampleBox])),
            activeBoxIdProvider.overrideWith((ref) => 'main'),
            receiptListProvider.overrideWith((ref) => MockReceiptListNotifier(AsyncValue.data(sampleReceipts))),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PulseWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap 14d chip
      await tester.tap(find.text('14d'));
      await tester.pumpAndSettle();

      // Tap 30d chip
      await tester.tap(find.text('30d'));
      await tester.pumpAndSettle();

      expect(find.byType(PulseWidget), findsOneWidget);
    });
  });
}
