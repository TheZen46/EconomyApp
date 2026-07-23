import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/home_page.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/model_update_provider.dart';

void main() {
  testWidgets('Search bar expansion overflow check', (WidgetTester tester) async {
    final List<FlutterErrorDetails> errors = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details);
      originalOnError?.call(details);
    };

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptListProvider.overrideWith((ref) => FakeReceiptListNotifier()),
          modelUpdateServiceProvider.overrideWith((ref) => FakeModelUpdateService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: HomePage(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final searchIcon = find.byIcon(Icons.search);
    expect(searchIcon, findsOneWidget);
    await tester.tap(searchIcon);

    // Pump frame by frame to catch overflow during animation
    for(int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
    }
    
    // Check if any error is an overflow
    final overflowErrors = errors.where((e) => e.exceptionAsString().contains('overflowed')).toList();
    
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    FlutterError.onError = originalOnError;

    expect(overflowErrors, isEmpty, reason: 'Layout overflow detected:\n${overflowErrors.map((e) => e.exceptionAsString()).join('\n')}');
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
