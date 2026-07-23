import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/home_page.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

import 'package:t_aidy/features/receipt_scanning/domain/repositories/receipt_repository.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/model_update_provider.dart';

void main() {
  testWidgets('HomePage layout does not overflow on desktop sizes', (WidgetTester tester) async {
    final List<FlutterErrorDetails> errors = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details);
      originalOnError?.call(details);
    };

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

    await tester.pump(const Duration(milliseconds: 1500));

    // Check if any of the errors are layout overflows
    final overflowErrors = errors.where((e) => e.exceptionAsString().toLowerCase().contains('overflow')).toList();

    expect(overflowErrors, isEmpty, reason: 'Layout overflow detected:\n${overflowErrors.map((e) => e.exceptionAsString()).join('\n')}');

    // Reset surface size
    await tester.binding.setSurfaceSize(null);
    FlutterError.onError = originalOnError;
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
