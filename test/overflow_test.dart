import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Search bar expansion causes overflow', (WidgetTester tester) async {
    // Set a predictable screen size
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;

    bool isSearchExpanded = true;
    final screenWidth = 800.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  const Text('tAIdy', style: TextStyle(fontSize: 24)),
                  const Spacer(),
                  Container(
                    width: isSearchExpanded ? screenWidth - 32 : 44,
                    height: 44,
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // We expect the tester to report an overflow exception
    final dynamic exception = tester.takeException();
    if (exception != null) {
      print('EXCEPTION CAUGHT: $exception');
    } else {
      print('NO EXCEPTION');
    }
  });
}
