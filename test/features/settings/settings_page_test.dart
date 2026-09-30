import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/settings/presentation/pages/settings_page.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';

class _FakeBoxesNotifier extends BoxesNotifier {
  _FakeBoxesNotifier([List<BoxModel>? initial]) {
    state = initial ?? [
      BoxModel(
        id: 'main',
        name: 'Out of the Box (Main Life)',
        budget: 0,
        spent: 0,
        currency: 'USD',
        color: 0xFF000000,
        icon: 'Home',
      ),
      BoxModel(
        id: 'box-consulting',
        name: 'Consulting & Freelance LLC',
        budget: 5000,
        spent: 1200,
        currency: 'USD',
        color: 0xFF002FA7,
        icon: 'Business',
      ),
    ];
  }
}

class _FakeReceiptListNotifier extends StateNotifier<AsyncValue<List<Receipt>>> implements ReceiptListNotifier {
  _FakeReceiptListNotifier(List<Receipt> receipts) : super(AsyncValue.data(receipts));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late Box settingsBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('t_aidy_settings_test_');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox('settings_test_box');
  });

  tearDownAll(() async {
    await settingsBox.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  final defaultReceipts = [
    Receipt(
      id: 'rec-test-1',
      merchantName: 'Acme Hardware Store',
      date: DateTime(2026, 3, 15),
      time: '14:30',
      totalAmount: 150.0,
      currency: 'USD',
      items: const [
        ReceiptItem(
          description: 'Desk Monitor Mount',
          quantity: 1,
          unitPrice: 150.0,
          totalPrice: 150.0,
          necessity: ItemNecessity.essential,
          mainCategory: 'Office Equipment',
        ),
      ],
      vatNumber: 'US-99281',
      merchantAddress: '100 Silicon Ave, San Francisco, CA',
      boxId: 'box-consulting',
    ),
  ];

  Widget buildSettingsWidget({
    List<Receipt>? receipts,
    List<BoxModel>? boxes,
  }) {
    return ProviderScope(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        boxesProvider.overrideWith((ref) => _FakeBoxesNotifier(boxes)),
        receiptListProvider.overrideWith((ref) => _FakeReceiptListNotifier(receipts ?? defaultReceipts)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SettingsPanelWidget(),
        ),
      ),
    );
  }

  group('Flow 6: Cryptographic Vault Controls & Local Sync Management (Gemini Antigravity)', () {
    testWidgets('renders top live cryptographic status card with Merkle root and air-gapped badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildSettingsWidget());
      await tester.pumpAndSettle();

      // 1. Verify Top Live Status Card
      expect(find.text('VAULT HEALTH & KEY INTEGRITY'), findsOneWidget);
      expect(find.text('AIR-GAPPED'), findsOneWidget);
      expect(find.textContaining('SHA-256 Merkle Root:'), findsOneWidget);
      expect(find.textContaining('RAM Key: Zeroed on Lock'), findsOneWidget);
      expect(find.textContaining('Cloud: AIR-GAPPED'), findsOneWidget);

      // 2. Tap Status Card to open Cryptographic Proofs Dialog
      await tester.tap(find.textContaining('SHA-256 Merkle Root:'));
      await tester.pumpAndSettle();

      expect(find.text('Vault Health & Cryptographic Proofs'), findsOneWidget);
      expect(find.text('RAM Master Key'), findsOneWidget);
      expect(find.text('Storage Topology'), findsOneWidget);
      expect(find.text('Cryptographic Seal'), findsOneWidget);

      // Close modal
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('renders Master Section 1: Cryptographic Vault & Biometrics with Anticipatory Export Triggers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildSettingsWidget());
      await tester.pumpAndSettle();

      // Master Section 1 Header
      expect(find.text('CRYPTOGRAPHIC VAULT & BIOMETRICS'), findsOneWidget);

      // 1. Biometric Lock
      expect(find.text('Biometric Lock (FaceID / Fingerprint)'), findsOneWidget);
      expect(find.text('Locks memory keys after 5 minutes of inactivity'), findsOneWidget);

      // 2. Sealed Cryptographic Audit Pack (.zip)
      expect(find.text('Sealed Cryptographic Audit Pack (.zip)'), findsOneWidget);
      expect(find.textContaining('Includes Merkle JSON-LD manifest'), findsOneWidget);
      expect(find.text('Generate .ZIP'), findsOneWidget);

      // 3. Sanitized CPA Tax Portal (.html)
      expect(find.text('Sanitized CPA Tax Portal (.html)'), findsOneWidget);
      expect(find.textContaining('Redacts PII with salted TIN hashes'), findsOneWidget);
      expect(find.text('Generate .HTML'), findsOneWidget);

      // 4. Continuous Learning Corpus (JSONL)
      expect(find.text('Continuous Learning Corpus (JSONL)'), findsOneWidget);
      expect(find.text('Inspect / Export'), findsOneWidget);

      // 5. Local AI Brain Models
      expect(find.text('Local AI Brain Models'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);

      // 6. AI Model Training Contribution
      expect(find.text('AI Model Training Contribution'), findsOneWidget);
    });

    testWidgets('renders Master Section 2: Multi-Box & Statutory Tax Profiles with statutory rate picker', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildSettingsWidget());
      await tester.pumpAndSettle();

      // Scroll to Master Section 2
      final headerFinder = find.text('MULTI-BOX & STATUTORY TAX PROFILES');
      await tester.scrollUntilVisible(headerFinder, 300);
      await tester.pumpAndSettle();

      // Master Section 2 Header
      expect(headerFinder, findsOneWidget);

      // 1. Monthly Budget
      expect(find.text('Monthly Budget'), findsOneWidget);

      // 2. Statutory Tax Shield Profile
      expect(find.text('Statutory Tax Shield Profile'), findsOneWidget);
      expect(find.textContaining('Auto-Stash Reserve'), findsOneWidget);

      // 3. Multi-Box Entity Containers
      expect(find.text('Multi-Box Entity Containers'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);

      // 4. Manage Categories & Taxonomy
      expect(find.text('Manage Categories & Taxonomy'), findsOneWidget);

      // 5. Active Inference Engine & Telemetry Diagnostics
      expect(find.text('ACTIVE INFERENCE ENGINE'), findsOneWidget);
      expect(find.text('Benchmark Local LLM'), findsOneWidget);
      expect(find.text('Run Test'), findsOneWidget);

      // 6. Dark Mode
      expect(find.text('Dark Mode'), findsOneWidget);

      // Tap Statutory Tax Shield Profile to open profile selection modal
      await tester.tap(find.text('Statutory Tax Shield Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Select Statutory Tax Profile'), findsOneWidget);
      expect(find.text('US 1099 Solopreneur (25%)'), findsOneWidget);
      expect(find.text('Italy Regime Forfettario (15%)'), findsOneWidget);
      expect(find.text('UK Sole Trader (29%)'), findsOneWidget);

      // Select Italy Regime Forfettario (15%)
      await tester.tap(find.text('Italy Regime Forfettario (15%)'));
      await tester.pumpAndSettle();

      // Verify that the rate updated
      expect(find.text('15% Rate'), findsOneWidget);
    });

    testWidgets('renders Master Section 3: Optical/P2P Air-Gapped Sync & Backups', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildSettingsWidget());
      await tester.pumpAndSettle();

      // Scroll to Master Section 3
      final section3Finder = find.text('OPTICAL/P2P AIR-GAPPED SYNC & BACKUPS');
      await tester.scrollUntilVisible(section3Finder, 300);
      await tester.pumpAndSettle();

      // Master Section 3 Header
      expect(section3Finder, findsOneWidget);

      // 1. Optical Animated QR Vault Sync
      expect(find.text('Optical Animated QR Vault Sync'), findsOneWidget);
      expect(find.text('Start Sync'), findsOneWidget);

      // 2. Sync Center & Local Outbox
      expect(find.text('Sync Center & Local Outbox'), findsOneWidget);
      expect(find.text('Replicate Cloud Data'), findsOneWidget);
      expect(find.text('Sync Now'), findsOneWidget);

      // 3. Import Bank CSV
      expect(find.text('Import Bank CSV'), findsOneWidget);

      // 4. Integrations & Webhooks
      expect(find.text('Integrations & Webhooks'), findsOneWidget);

      // 5. Destructive & Sign Out actions
      final clearFinder = find.text('Clear All Vault Data');
      await tester.scrollUntilVisible(clearFinder, 200);
      await tester.pumpAndSettle();

      expect(clearFinder, findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    });
  });
}
