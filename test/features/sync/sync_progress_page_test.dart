import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/sync/presentation/widgets/kinetic_sync_progress_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KineticSyncProgressBar Widget Tests', () {
    testWidgets('renders progress percentage and speed label accurately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KineticSyncProgressBar(
              progress: 0.65,
              isDark: true,
              speedLabel: '3.4 MB/s',
            ),
          ),
        ),
      );

      expect(find.text('SYNC ENGINE'), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('3.4 MB/s'), findsOneWidget);

      // Verify custom painter is rendered
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles 0% and 100% boundary states gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KineticSyncProgressBar(
              progress: 0.0,
              isDark: false,
            ),
          ),
        ),
      );

      expect(find.text('0%'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KineticSyncProgressBar(
              progress: 1.0,
              isDark: false,
            ),
          ),
        ),
      );

      expect(find.text('100%'), findsOneWidget);
    });
  });
}
