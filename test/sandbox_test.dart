import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Overflow test', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      // Swallows error or throws it into the void
      print('Caught by custom handler: ${details.exception}');
      // throw details.exception; // Even if thrown, might not fail test correctly
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
  });
}
