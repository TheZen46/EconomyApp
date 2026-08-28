import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/invoices/data/providers/invoices_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<InvoiceModel> invoiceBox;
  late Box settingsBox;
  late InvoicesNotifier notifier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('invoices_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(InvoiceModelAdapter());
    }

    invoiceBox = await Hive.openBox<InvoiceModel>('invoices_test_box');
    settingsBox = await Hive.openBox('settings_test_box');
    notifier = InvoicesNotifier(invoiceBox, settingsBox);
  });

  tearDown(() async {
    await invoiceBox.close();
    await settingsBox.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('InvoicesNotifier - Monotonic & Unique Invoice Numbering', () {
    test('generates sequential collision-free invoice numbers matching format INV-YYYYMM-XXXX', () async {
      final now = DateTime(2026, 8, 15);
      final inv1 = await notifier.create(
        clientName: 'Client Alpha',
        amount: 1500.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
      );

      final inv2 = await notifier.create(
        clientName: 'Client Beta',
        amount: 2500.0,
        status: InvoiceStatus.sent,
        issuedDate: now,
      );

      expect(inv1.invoiceNumber, 'INV-202608-0001');
      expect(inv2.invoiceNumber, 'INV-202608-0002');
      expect(notifier.state.length, 2);
    });

    test('deleting previous invoices never reuses or regresses invoice numbers', () async {
      final now = DateTime(2026, 8, 15);

      final inv1 = await notifier.create(
        clientName: 'Client 1',
        amount: 100.0,
        status: InvoiceStatus.sent,
        issuedDate: now,
      );
      final inv2 = await notifier.create(
        clientName: 'Client 2',
        amount: 200.0,
        status: InvoiceStatus.sent,
        issuedDate: now,
      );

      expect(inv1.invoiceNumber, 'INV-202608-0001');
      expect(inv2.invoiceNumber, 'INV-202608-0002');

      // Delete the first invoice
      await notifier.delete(inv1.id);
      expect(notifier.state.length, 1);

      // Create a 3rd invoice — MUST be 0003, NEVER 0001 or 0002
      final inv3 = await notifier.create(
        clientName: 'Client 3',
        amount: 300.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
      );
      expect(inv3.invoiceNumber, 'INV-202608-0003');

      // Delete the 2nd and 3rd invoices (now list is empty)
      await notifier.delete(inv2.id);
      await notifier.delete(inv3.id);
      expect(notifier.state.isEmpty, isTrue);

      // Create a 4th invoice — MUST be 0004, NEVER 0001
      final inv4 = await notifier.create(
        clientName: 'Client 4',
        amount: 400.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
      );
      expect(inv4.invoiceNumber, 'INV-202608-0004');
    });

    test('scanning existing box entries calculates absolute highest sequence index', () async {
      final now = DateTime(2026, 8, 15);

      // Pre-populate box with existing invoices with gaps
      final preExisting = InvoiceModel(
        id: 'legacy-99',
        invoiceNumber: 'INV-202608-0099',
        clientName: 'Legacy Client',
        amount: 999.0,
        status: InvoiceStatus.settled,
        issuedDate: now,
      );
      await invoiceBox.put(preExisting.id, preExisting);

      // Reload notifier to simulate cold start
      final reloadedNotifier = InvoicesNotifier(invoiceBox, settingsBox);

      expect(reloadedNotifier.getMaxExistingInvoiceNumber(now), 99);

      final newInv = await reloadedNotifier.create(
        clientName: 'Next Client',
        amount: 500.0,
        status: InvoiceStatus.sent,
        issuedDate: now,
      );
      expect(newInv.invoiceNumber, 'INV-202608-0100');
    });

    test('createInvoice rejects duplicate invoice numbers', () async {
      final now = DateTime(2026, 8, 15);

      await notifier.create(
        clientName: 'Client A',
        amount: 100.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
        customInvoiceNumber: 'INV-202608-0001',
      );

      // Attempting to add duplicate custom number must throw
      expect(
        () async => await notifier.create(
          clientName: 'Client Duplicate',
          amount: 200.0,
          status: InvoiceStatus.draft,
          issuedDate: now,
          customInvoiceNumber: 'INV-202608-0001',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('verifies invoice number uniqueness across multiple create/delete cycles', () async {
      final now = DateTime(2026, 8, 15);
      final generatedNumbers = <String>{};

      for (int i = 1; i <= 20; i++) {
        final inv = await notifier.create(
          clientName: 'Batch Client $i',
          amount: i * 50.0,
          status: InvoiceStatus.draft,
          issuedDate: now,
        );

        // Verify uniqueness
        expect(generatedNumbers.contains(inv.invoiceNumber), isFalse,
            reason: 'Duplicate invoice number generated: ${inv.invoiceNumber}');
        generatedNumbers.add(inv.invoiceNumber);

        // Periodically delete invoices to simulate churn
        if (i % 3 == 0) {
          await notifier.delete(inv.id);
        }
      }

      expect(generatedNumbers.length, 20);
    });
  });

  group('InvoicesNotifier - Immutable State & Status Updates', () {
    test('updateInvoiceStatus constructs new instance, updates Hive, and emits new list state', () async {
      final now = DateTime(2026, 8, 15);
      final inv = await notifier.create(
        clientName: 'Acme Corp',
        amount: 1200.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
      );

      expect(inv.status, InvoiceStatus.draft);
      final initialList = notifier.state;

      // Track listener notifications
      final notifications = <List<InvoiceModel>>[];
      notifier.addListener((state) {
        notifications.add(state);
      });

      // Update invoice status to Sent
      await notifier.updateInvoiceStatus(inv.id, InvoiceStatus.sent);

      // Verify list state is new reference
      expect(identical(notifier.state, initialList), isFalse);
      expect(notifier.state.first.status, InvoiceStatus.sent);

      // Verify Hive is updated
      final fromHive = invoiceBox.get(inv.id);
      expect(fromHive?.status, InvoiceStatus.sent);

      // Verify listener was notified with new state
      expect(notifications.isNotEmpty, isTrue);
      expect(notifications.last.first.status, InvoiceStatus.sent);

      // Update to Settled via alias updateStatus
      await notifier.updateStatus(inv.id, InvoiceStatus.settled);
      expect(notifier.state.first.status, InvoiceStatus.settled);
      expect(invoiceBox.get(inv.id)?.status, InvoiceStatus.settled);
    });

    test('KPI metrics calculate accurate outstanding, overdue, and draft totals', () async {
      final now = DateTime(2026, 8, 15);

      await notifier.create(
        clientName: 'Draft Client',
        amount: 300.0,
        status: InvoiceStatus.draft,
        issuedDate: now,
      );

      await notifier.create(
        clientName: 'Sent Client',
        amount: 700.0,
        status: InvoiceStatus.sent,
        issuedDate: now,
      );

      final overdueInv = await notifier.create(
        clientName: 'Overdue Client',
        amount: 500.0,
        status: InvoiceStatus.draft,
        issuedDate: now.subtract(const Duration(days: 40)),
        dueDate: now.subtract(const Duration(days: 10)),
      );
      await notifier.updateInvoiceStatus(overdueInv.id, InvoiceStatus.overdue);

      await notifier.create(
        clientName: 'Settled Client',
        amount: 1000.0,
        status: InvoiceStatus.settled,
        issuedDate: now,
      );

      expect(notifier.totalDraft, 300.0);
      expect(notifier.totalOverdue, 500.0);
      expect(notifier.totalOutstanding, 1200.0); // Sent (700) + Overdue (500)
    });

    test('auto-marks overdue invoices on reload when due date has passed', () async {
      final now = DateTime(2026, 8, 15);

      final pastDueInvoice = InvoiceModel(
        id: 'past-due-1',
        invoiceNumber: 'INV-202608-0050',
        clientName: 'Late Payer',
        amount: 450.0,
        status: InvoiceStatus.sent,
        issuedDate: now.subtract(const Duration(days: 60)),
        dueDate: now.subtract(const Duration(days: 15)),
      );
      await invoiceBox.put(pastDueInvoice.id, pastDueInvoice);

      final reloadedNotifier = InvoicesNotifier(invoiceBox, settingsBox);
      expect(reloadedNotifier.state.first.status, InvoiceStatus.overdue);
      expect(invoiceBox.get('past-due-1')?.status, InvoiceStatus.overdue);
    });
  });
}
