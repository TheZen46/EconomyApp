import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/invoice_model.dart';

final invoicesHiveBoxProvider = Provider<Box<InvoiceModel>>((ref) {
  throw UnimplementedError('invoicesHiveBoxProvider must be overridden in main.dart');
});

class InvoicesNotifier extends StateNotifier<List<InvoiceModel>> {
  final Box<InvoiceModel> _box;
  static const _uuid = Uuid();
  int _invoiceCounter = 0;

  InvoicesNotifier(this._box) : super([]) {
    _load();
  }

  void _load() {
    final items = _box.values.toList()
      ..sort((a, b) => b.issuedDate.compareTo(a.issuedDate));
    _invoiceCounter = items.length;
    // Auto-mark overdue
    for (final inv in items) {
      if (inv.isOverdue && inv.status == InvoiceStatus.sent) {
        inv.status = InvoiceStatus.overdue;
        _box.put(inv.id, inv);
      }
    }
    state = items;
  }

  String _generateNumber() {
    _invoiceCounter++;
    final year = DateTime.now().year;
    return 'INV-$year-${_invoiceCounter.toString().padLeft(3, '0')}';
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
      invoiceNumber: _generateNumber(),
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
  return InvoicesNotifier(box);
});
