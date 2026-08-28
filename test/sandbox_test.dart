import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Overflow test', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Swallows error or throws it into the void
      debugPrint('Caught by custom handler: ${details.exception}');
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Container(width: 10000, height: 10, color: Colors.red),
            ],
          ),
        ),
      ),
    );

    FlutterError.onError = originalOnError;
  });
}
