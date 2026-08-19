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
  final Box<InvoiceModel> _box;
  final Box _settingsBox;
  static const _uuid = Uuid();

  InvoicesNotifier(this._box, this._settingsBox) : super([]) {
    _load();
  }

  void _load() {
    final items = _box.values.toList()
      ..sort((a, b) => b.issuedDate.compareTo(a.issuedDate));
    // Auto-mark overdue — do NOT set _invoiceCounter from items.length
    for (final inv in items) {
      if (inv.isOverdue && inv.status == InvoiceStatus.sent) {
        inv.status = InvoiceStatus.overdue;
        _box.put(inv.id, inv);
      }
    }
    state = items;
  }

  /// Returns the next invoice number using a monotonically increasing counter
  /// persisted in Hive. Safe against deletions — the counter only ever goes up.
  Future<String> _generateNumber() async {
    final current = _settingsBox.get(_counterKey, defaultValue: 0) as int;
    final next = current + 1;
    await _settingsBox.put(_counterKey, next);
    final year = DateTime.now().year;
    return 'INV-$year-${next.toString().padLeft(3, '0')}';
  }

  Future<InvoiceModel> create({
    required String clientName,
    required double amount,
    required String status,
    required DateTime issuedDate,
    DateTime? dueDate,
    String notes = '',
    String currency = 'USD',
  }) async {
    final inv = InvoiceModel(
      id: _uuid.v4(),
      invoiceNumber: await _generateNumber(),
      clientName: clientName,
      amount: amount,
      status: status,
      issuedDate: issuedDate,
      dueDate: dueDate,
      notes: notes,
      currency: currency,
    );
    await _box.put(inv.id, inv);
    state = [inv, ...state];
    return inv;
  }

  Future<void> updateStatus(String id, String newStatus) async {
    final inv = state.firstWhere((i) => i.id == id);
    final updated = inv.copyWith(status: newStatus);
    await _box.put(id, updated);
    state = state.map((i) => i.id == id ? updated : i).toList();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    state = state.where((i) => i.id != id).toList();
    // Counter is NOT decremented — it must only ever increase.
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
  final box = ref.watch(invoicesHiveBoxProvider);
  final settingsBox = ref.watch(settingsBoxProvider);
  return InvoicesNotifier(box, settingsBox);
});
