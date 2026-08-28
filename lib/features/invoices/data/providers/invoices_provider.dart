import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/invoice_model.dart';
import '../../../../features/receipt_scanning/presentation/providers/receipt_provider.dart';

final invoicesHiveBoxProvider = Provider<Box<InvoiceModel>>((ref) {
  throw UnimplementedError('invoicesHiveBoxProvider must be overridden in main.dart');
});

// ── Persistent counter key ───────────────────────────────────────────────────
// Stored in the unencrypted settingsBox. It is increment-only and never
// derived from the list length, so deleting invoices cannot cause reuse.
const _counterKey = 'global_invoice_counter';

class InvoicesNotifier extends StateNotifier<List<InvoiceModel>> {
  final Box<InvoiceModel>? _box;
  final Box? _settingsBox;
  static const _uuid = Uuid();

  InvoicesNotifier([this._box, this._settingsBox]) : super([]) {
    _load();
  }

  void _load() {
    final items = _box?.values.toList() ?? [];
    items.sort((a, b) => b.issuedDate.compareTo(a.issuedDate));

    // Auto-mark overdue using copyWith — never mutate in-place.
    final updated = items.map((inv) {
      if (inv.isOverdue && inv.status == InvoiceStatus.sent) {
        final updatedInv = inv.copyWith(status: InvoiceStatus.overdue);
        _box?.put(inv.id, updatedInv);
        return updatedInv;
      }
      return inv;
    }).toList();

    state = [...updated];
  }

  /// Scans all existing box entries (and in-memory state) to determine the
  /// absolute highest existing sequence index for the given month/year.
  int getMaxExistingInvoiceNumber([DateTime? date]) {
    final targetDate = date ?? DateTime.now();
    final year = targetDate.year.toString();
    final month = targetDate.month.toString().padLeft(2, '0');
    final targetPrefix = 'INV-$year$month-';

    int maxNumber = 0;

    final allInvoices = _box?.values.toList() ?? state;
    for (final inv in allInvoices) {
      final numStr = inv.invoiceNumber.trim();
      if (numStr.startsWith(targetPrefix)) {
        final suffix = numStr.substring(targetPrefix.length);
        final parsed = int.tryParse(suffix);
        if (parsed != null && parsed > maxNumber) {
          maxNumber = parsed;
        }
      } else {
        // Also inspect older formats like INV-2026-001 or INV-001
        final match = RegExp(r'INV-(?:\d{6}|\d{4})?-?(\d+)').firstMatch(numStr) ??
            RegExp(r'(\d+)$').firstMatch(numStr);
        if (match != null) {
          final parsed = int.tryParse(match.group(1)!);
          if (parsed != null && parsed > maxNumber) {
            maxNumber = parsed;
          }
        }
      }
    }

    final persisted = _settingsBox?.get(_counterKey, defaultValue: 0) as int? ?? 0;
    if (persisted > maxNumber) {
      maxNumber = persisted;
    }

    return maxNumber;
  }

  /// Checks whether an invoice number is already taken in the database.
  bool isInvoiceNumberTaken(String invoiceNumber) {
    final allInvoices = _box?.values.toList() ?? state;
    return allInvoices.any(
      (inv) => inv.invoiceNumber.toLowerCase().trim() == invoiceNumber.toLowerCase().trim(),
    );
  }

  /// Returns the next invoice number using a monotonic sequence generator:
  /// `INV-${year}${month}-${(maxExistingInvoiceNumber + 1).padLeft(4, '0')}`.
  ///
  /// Guarantees that deleting prior invoices NEVER causes sequence reuse or collision.
  Future<String> generateNextInvoiceNumber([DateTime? date]) async {
    final now = date ?? DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    var nextIndex = getMaxExistingInvoiceNumber(now) + 1;

    var candidate = 'INV-$year$month-${nextIndex.toString().padLeft(4, '0')}';
    while (isInvoiceNumberTaken(candidate)) {
      nextIndex++;
      candidate = 'INV-$year$month-${nextIndex.toString().padLeft(4, '0')}';
    }

    await _settingsBox?.put(_counterKey, nextIndex);
    return candidate;
  }

  /// Creates a new invoice with collision-free numbering and a duplicate rejection check.
  Future<InvoiceModel> createInvoice({
    required String clientName,
    required double amount,
    required String status,
    required DateTime issuedDate,
    DateTime? dueDate,
    String notes = '',
    String currency = 'USD',
    String? customInvoiceNumber,
  }) async {
    final invoiceNumber = customInvoiceNumber ?? await generateNextInvoiceNumber(issuedDate);

    // Uniqueness validation
    if (isInvoiceNumberTaken(invoiceNumber)) {
      throw StateError(
        'Invoice number "$invoiceNumber" already exists. Duplicate invoice numbers are rejected.',
      );
    }

    final inv = InvoiceModel(
      id: _uuid.v4(),
      invoiceNumber: invoiceNumber,
      clientName: clientName,
      amount: amount,
      status: status,
      issuedDate: issuedDate,
      dueDate: dueDate,
      notes: notes,
      currency: currency,
    );

    await _box?.put(inv.id, inv);
    state = [inv, ...state];
    return inv;
  }

  /// Alias for [createInvoice].
  Future<InvoiceModel> create({
    required String clientName,
    required double amount,
    required String status,
    required DateTime issuedDate,
    DateTime? dueDate,
    String notes = '',
    String currency = 'USD',
    String? customInvoiceNumber,
  }) =>
      createInvoice(
        clientName: clientName,
        amount: amount,
        status: status,
        issuedDate: issuedDate,
        dueDate: dueDate,
        notes: notes,
        currency: currency,
        customInvoiceNumber: customInvoiceNumber,
      );

  /// Updates an invoice's status immutably, persists the updated instance to Hive,
  /// and emits a new immutable list state to trigger reactive UI re-renders.
  Future<void> updateInvoiceStatus(String id, String newStatus) async {
    final existing = state.firstWhere((i) => i.id == id);
    final updatedInvoice = existing.copyWith(status: newStatus);
    await _box?.put(id, updatedInvoice);
    state = state.map((inv) => inv.id == id ? updatedInvoice : inv).toList();
  }

  /// Alias for [updateInvoiceStatus].
  Future<void> updateStatus(String id, String newStatus) => updateInvoiceStatus(id, newStatus);

  Future<void> delete(String id) async {
    await _box?.delete(id);
    state = state.where((i) => i.id != id).toList();
    // Monotonic sequence counter is NEVER decremented upon deletion.
  }

  // Stats
  double get totalOutstanding => state
      .where((i) => i.status == InvoiceStatus.sent || i.status == InvoiceStatus.overdue)
      .fold(0, (sum, i) => sum + i.amount);

  double get totalOverdue => state
      .where((i) => i.status == InvoiceStatus.overdue)
      .fold(0, (sum, i) => sum + i.amount);

  double get totalDraft => state
      .where((i) => i.status == InvoiceStatus.draft)
      .fold(0, (sum, i) => sum + i.amount);
}

final invoicesProvider = StateNotifierProvider<InvoicesNotifier, List<InvoiceModel>>((ref) {
  try {
    final box = ref.watch(invoicesHiveBoxProvider);
    final settingsBox = ref.watch(settingsBoxProvider);
    return InvoicesNotifier(box, settingsBox);
  } catch (_) {
    return InvoicesNotifier(null, null);
  }
});
