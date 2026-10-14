import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/invoice_model.dart';
import '../../../../features/receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../../core/sync/outbox_service.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/providers/supabase_providers.dart';

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
  final OutboxService? _outboxService;
  final SupabaseClient? _supabase;
  final String? _devicePartition;
  static const _uuid = Uuid();

  InvoicesNotifier([
    this._box,
    this._settingsBox,
    this._outboxService,
    this._supabase,
    this._devicePartition,
  ]) : super([]) {
    _load();
  }

  void _load() {
    final items = _box?.values.toList() ?? [];
    items.sort((a, b) => b.issuedDate.compareTo(a.issuedDate));

    // Auto-mark overdue using copyWith with updatedAt and incremented version,
    // and synchronize through the outbox to prevent remote pull revert churn.
    final updated = items.map((inv) {
      if (inv.isOverdue && inv.status == InvoiceStatus.sent) {
        final nowUtc = DateTime.now().toUtc();
        final updatedInv = inv.copyWith(
          status: InvoiceStatus.overdue,
          updatedAt: nowUtc,
          version: inv.version + 1,
        );
        _box?.put(inv.id, updatedInv);
        if (_outboxService != null) {
          _outboxService.enqueue(
            entityType: 'invoice',
            entityId: inv.id,
            mutationType: 'upsert',
            payload: updatedInv.toJson(),
          ).catchError((e) {
            debugPrint('InvoicesNotifier: Error enqueuing overdue transition: $e');
            return null as dynamic;
          });
        }
        return updatedInv;
      }
      return inv;
    }).toList();

    state = [...updated];
  }

  /// Reloads state from Hive box to synchronize with background sync deltas.
  void reload() {
    _load();
  }

  String _counterKeyFor(String yearMonth, [String? partition]) {
    final part = (partition != null && partition.isNotEmpty) ? '_$partition' : '';
    return 'invoice_counter_$yearMonth$part';
  }

  /// Scans all existing box entries (and in-memory state) to determine the
  /// absolute highest existing sequence index for the given month/year and optional device partition.
  int getMaxExistingInvoiceNumber([DateTime? date, String? partition]) {
    final targetDate = date ?? DateTime.now();
    final year = targetDate.year.toString();
    final month = targetDate.month.toString().padLeft(2, '0');
    final yearMonth = '$year$month';
    final effectivePartition = partition ?? _devicePartition ?? (_settingsBox?.get('invoice_device_partition') as String?);
    final partitionTag = (effectivePartition != null && effectivePartition.isNotEmpty) ? '-$effectivePartition' : '';
    final targetPrefix = 'INV-$yearMonth$partitionTag-';

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
      } else if (effectivePartition == null || effectivePartition.isEmpty) {
        if (numStr.startsWith('INV-$yearMonth-')) {
          final suffix = numStr.substring('INV-$yearMonth-'.length);
          final parsed = int.tryParse(suffix);
          if (parsed != null && parsed > maxNumber) {
            maxNumber = parsed;
          }
        } else {
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
    }

    final scopedPersisted = _settingsBox?.get(_counterKeyFor(yearMonth, effectivePartition)) as int?;
    final legacyPersisted = (effectivePartition == null || effectivePartition.isEmpty)
        ? (_settingsBox?.get(_counterKey, defaultValue: 0) as int? ?? 0)
        : 0;
    final persisted = scopedPersisted ?? legacyPersisted;
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
  /// `INV-${year}${month}-${(maxExistingInvoiceNumber + 1).padLeft(4, '0')}` (or with device partition).
  ///
  /// Guarantees that deleting prior invoices NEVER causes sequence reuse or collision.
  Future<String> generateNextInvoiceNumber([DateTime? date]) async {
    final now = date ?? DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final yearMonth = '$year$month';
    final effectivePartition = _devicePartition ?? (_settingsBox?.get('invoice_device_partition') as String?);

    // 1. If Supabase is connected, attempt server-side sequence allocation (RPC with row locking)
    if (_supabase != null) {
      try {
        final res = await _supabase.rpc('allocate_invoice_number', params: {
          'p_year_month': yearMonth,
          'p_partition': effectivePartition,
        });
        if (res != null && res is String && res.isNotEmpty) {
          return res;
        }
      } catch (_) {
        // Fall back to local device-partitioned sequence generator
      }
    }

    // 2. Local partitioned monotonic allocation
    var nextIndex = getMaxExistingInvoiceNumber(now, effectivePartition) + 1;
    final partitionTag = (effectivePartition != null && effectivePartition.isNotEmpty)
        ? '-$effectivePartition'
        : '';

    var candidate = 'INV-$year$month$partitionTag-${nextIndex.toString().padLeft(4, '0')}';
    while (isInvoiceNumberTaken(candidate)) {
      nextIndex++;
      candidate = 'INV-$year$month$partitionTag-${nextIndex.toString().padLeft(4, '0')}';
    }

    await _settingsBox?.put(_counterKeyFor(yearMonth, effectivePartition), nextIndex);
    if (effectivePartition == null || effectivePartition.isEmpty) {
      await _settingsBox?.put(_counterKey, nextIndex);
    }
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

    final nowUtc = DateTime.now().toUtc();
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
      createdAt: nowUtc,
      updatedAt: nowUtc,
    );

    final previous = state;
    try {
      await _box?.put(inv.id, inv);
      if (!mounted) return inv;
      state = [inv, ...state];

      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'invoice',
          entityId: inv.id,
          mutationType: 'upsert',
          payload: inv.toJson(),
        );
      }

      return inv;
    } catch (e) {
      debugPrint('InvoicesNotifier: Error creating invoice: $e');
      if (mounted) state = previous;
      rethrow;
    }
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
    final previous = state;
    try {
      final existing = state.firstWhere((i) => i.id == id);
      final updatedInvoice = existing.copyWith(
        status: newStatus,
        updatedAt: DateTime.now().toUtc(),
        version: existing.version + 1,
      );
      await _box?.put(id, updatedInvoice);
      if (!mounted) return;
      state = state.map((inv) => inv.id == id ? updatedInvoice : inv).toList();

      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'invoice',
          entityId: id,
          mutationType: 'upsert',
          payload: updatedInvoice.toJson(),
        );
      }
    } catch (e) {
      debugPrint('InvoicesNotifier: Error updating invoice: $e');
      if (mounted) state = previous;
      rethrow;
    }
  }

  /// Alias for [updateInvoiceStatus].
  Future<void> updateStatus(String id, String newStatus) => updateInvoiceStatus(id, newStatus);

  Future<void> delete(String id) async {
    final previous = state;
    try {
      await _box?.delete(id);
      if (!mounted) return;
      state = state.where((i) => i.id != id).toList();

      if (_outboxService != null) {
        await _outboxService.enqueue(
          entityType: 'invoice',
          entityId: id,
          mutationType: 'delete',
          payload: {'id': id},
        );
      }
    } catch (e) {
      debugPrint('InvoicesNotifier: Error deleting invoice: $e');
      if (mounted) state = previous;
      rethrow;
    }
    // Monotonic sequence counter is NEVER decremented upon deletion.
  }

  // Stats - computed from effectiveStatus for real-time accuracy
  double get totalOutstanding => state
      .where((i) => i.effectiveStatus == InvoiceStatus.sent || i.effectiveStatus == InvoiceStatus.overdue)
      .fold(0, (sum, i) => sum + i.amount);

  double get totalOverdue => state
      .where((i) => i.effectiveStatus == InvoiceStatus.overdue)
      .fold(0, (sum, i) => sum + i.amount);

  double get totalDraft => state
      .where((i) => i.effectiveStatus == InvoiceStatus.draft)
      .fold(0, (sum, i) => sum + i.amount);
}

final invoicesProvider = StateNotifierProvider<InvoicesNotifier, List<InvoiceModel>>((ref) {
  Box<InvoiceModel>? box;
  try {
    box = ref.watch(invoicesHiveBoxProvider);
  } catch (_) {}

  Box? settingsBox;
  try {
    settingsBox = ref.watch(settingsBoxProvider);
  } catch (_) {}

  OutboxService? outbox;
  try {
    outbox = ref.watch(outboxServiceProvider);
  } catch (_) {}

  final client = ref.watch(supabaseClientProvider);
  final devicePartition = settingsBox?.get('invoice_device_partition') as String?;

  return InvoicesNotifier(box, settingsBox, outbox, client, devicePartition);
});
