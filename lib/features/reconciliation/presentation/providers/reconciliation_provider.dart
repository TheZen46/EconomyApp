import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../data/datasources/statement_parser.dart';
import '../../data/models/statement_transaction.dart';
import '../../domain/reconciliation_engine.dart';

/// Presentation state for bank reconciliation.
class ReconciliationState {
  final List<ReconciliationMatch> matches;
  final bool isLoading;
  final String? errorMessage;

  const ReconciliationState({
    this.matches = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ReconciliationState copyWith({
    List<ReconciliationMatch>? matches,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ReconciliationState(
      matches: matches ?? this.matches,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  int get matchedCount => matches.where((m) => m.isMatched).length;
  int get totalCount => matches.length;
  int get matchPercentage =>
      totalCount > 0 ? ((matchedCount / totalCount) * 100).round() : 0;
}

/// Sample bank statement used for demo/testing workflows.
const kSampleBankStatementCsv = '''Date,Description,Amount,Currency
2026-03-15,Adobe Creative Cloud,59.99,USD
2026-03-14,Uber Trip San Francisco,28.50,USD
2026-03-12,Blue Bottle Coffee Co,6.75,USD
2026-03-10,GitHub Copilot Enterprise,21.00,USD
2026-03-08,Whole Foods Market,84.20,USD''';

/// Notifier that orchestrates statement parsing and reconciliation matching.
class ReconciliationNotifier extends StateNotifier<ReconciliationState> {
  final Ref _ref;

  ReconciliationNotifier(this._ref) : super(const ReconciliationState());

  /// Sets loading state explicitly.
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// Runs reconciliation between given parsed statement transactions and active receipts.
  void reconcileTransactions(List<StatementTransaction> txns) {
    state = state.copyWith(isLoading: true, errorMessage: null);

    List<Receipt> receipts = [];
    try {
      receipts = _ref.read(receiptListProvider).valueOrNull ?? [];
    } catch (_) {
      receipts = [];
    }

    final results = ReconciliationEngine.reconcile(
      transactions: txns,
      receipts: receipts,
    );

    state = state.copyWith(
      matches: results,
      isLoading: false,
    );
  }

  /// Parses raw statement file content based on file extension and executes reconciliation.
  bool loadFromContent(String content, String extension) {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final ext = extension.toLowerCase();
    List<StatementTransaction> parsed;

    if (ext == 'ofx' || ext == 'qbo') {
      parsed = StatementParser.parseOfx(content);
    } else {
      parsed = StatementParser.parseCsv(content);
    }

    if (parsed.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No transactions could be parsed from the statement file.',
      );
      return false;
    }

    reconcileTransactions(parsed);
    return true;
  }

  /// Loads sample built-in statement for demonstration purposes.
  void loadSampleStatement() {
    loadFromContent(kSampleBankStatementCsv, 'csv');
  }

  /// Resets reconciliation results.
  void reset() {
    state = const ReconciliationState();
  }
}

/// Provider for bank reconciliation workflow and matching results.
final reconciliationProvider =
    StateNotifierProvider<ReconciliationNotifier, ReconciliationState>((ref) {
  return ReconciliationNotifier(ref);
});
