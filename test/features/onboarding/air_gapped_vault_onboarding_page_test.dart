import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/onboarding/presentation/pages/air_gapped_vault_onboarding_page.dart';

class _FakeBoxesNotifier extends BoxesNotifier {
  _FakeBoxesNotifier([List<BoxModel>? initial]) {
    state = initial ?? [];
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AirGappedVaultOnboardingPage (Gemini Antigravity) Tests', () {
    testWidgets('renders air-gapped security banner, operating models, and live ledger simulation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boxesProvider.overrideWith((ref) => _FakeBoxesNotifier([])),
          ],
          child: const MaterialApp(
            home: AirGappedVaultOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Air-Gapped Security Banner
      expect(find.textContaining('AIR-GAPPED VAULT ACTIVE'), findsOneWidget);
      expect(find.text('Initialize Your Air-Gapped Ledger'), findsOneWidget);

      // 2. Verify Operating Models
      expect(find.text('Sole Proprietor / 1099 Freelancer'), findsOneWidget);
      expect(find.text('Single-Member LLC / S-Corp'), findsOneWidget);
      expect(find.text('Side Hustle / Part-Time Contractor'), findsOneWidget);

      // Default 25% for Sole Proprietor
      expect(find.textContaining('25% Tax Shield'), findsWidgets);

      // 3. Verify Live Ledger Simulation Mechanics
      expect(find.text('Sample Paid Client Invoice (INV-001)'), findsOneWidget);
      expect(find.text('+\$5,000.00'), findsOneWidget);
      expect(find.text('-\$1,250.00'), findsOneWidget); // 25% of $5,000
      expect(find.text('-\$15.00'), findsOneWidget); // Figma SaaS
      expect(find.text('\$3,735.00'), findsOneWidget); // Safe to spend: 5000 - 1250 - 15

      // 4. Test Switching Operating Model to Single-Member LLC (30% Tax Shield)
      await tester.tap(find.text('Single-Member LLC / S-Corp'));
      await tester.pumpAndSettle();

      // Updated calculations: 30% of $5,000 = $1,500; Safe to spend: 5000 - 1500 - 15 = $3,485.00
      expect(find.text('-\$1,500.00'), findsOneWidget);
      expect(find.text('\$3,485.00'), findsOneWidget);

      // 5. Verify Biometric Vault Keystore Card
      expect(find.text('Hardware Keystore & Memory Zeroing'), findsOneWidget);

      // 6. Verify Action Buttons
      expect(find.text('Initialize Air-Gapped Vault & Enter Ledger'), findsOneWidget);
      expect(find.text('Ingest First Receipt with Local VLM'), findsOneWidget);
    });

    testWidgets('initializes box and biometric key on primary CTA tap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      final fakeNotifier = _FakeBoxesNotifier([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boxesProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: AirGappedVaultOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap primary initialize action
      await tester.tap(find.text('Initialize Air-Gapped Vault & Enter Ledger'));
      await tester.pumpAndSettle();

      // Verify that the default box was seeded
      expect(fakeNotifier.state.isNotEmpty, true);
      expect(fakeNotifier.state.first.name, contains('Consulting & Client Services'));
    });
  });
}
