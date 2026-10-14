import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/financial/consolidated_statement_service.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

export '../../../../core/financial/consolidated_statement_service.dart'
    show ConsolidatedFinancialStatement, StatementLineItem, ConsolidatedStatementService;

/// Provider for consolidated financial statements across multiple entities.
final consolidatedStatementProvider = Provider<ConsolidatedFinancialStatement>((ref) {
  final boxes = ref.watch(boxesProvider);
  final invoices = ref.watch(invoicesProvider);
  final receipts = ref.watch(receiptListProvider).valueOrNull ?? [];

  return ConsolidatedStatementService.generateConsolidatedStatement(
    boxes: boxes,
    invoices: invoices,
    receipts: receipts,
    fiscalYear: DateTime.now().year,
  );
});
