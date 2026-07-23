import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/home_page.dart';

void main() {
  testWidgets('HomePage grid does not overflow on medium screens', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      throw details.exception;
    };

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HomePage(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
