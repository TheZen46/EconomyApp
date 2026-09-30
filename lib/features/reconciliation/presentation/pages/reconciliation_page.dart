import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../../../../core/theme/app_theme.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../data/datasources/statement_parser.dart';
import '../../data/models/statement_transaction.dart';
import '../../domain/reconciliation_engine.dart';

class ReconciliationPage extends ConsumerStatefulWidget {
  const ReconciliationPage({super.key});

  @override
  ConsumerState<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends ConsumerState<ReconciliationPage> {
  List<ReconciliationMatch> _matches = [];
  bool _isLoading = false;

  void _runReconciliation(List<StatementTransaction> txns) {
    final receipts = ref.read(receiptListProvider).valueOrNull ?? [];
    final results = ReconciliationEngine.reconcile(
      transactions: txns,
      receipts: receipts,
    );
    setState(() {
      _matches = results;
      _isLoading = false;
    });
  }

  Future<void> _pickStatementFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'ofx', 'qbo', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final content = await File(path).readAsString();
        final ext = result.files.single.extension?.toLowerCase() ?? '';

        List<StatementTransaction> parsed;
        if (ext == 'ofx' || ext == 'qbo') {
          parsed = StatementParser.parseOfx(content);
        } else {
          parsed = StatementParser.parseCsv(content);
        }

        if (parsed.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No transactions could be parsed from the statement file.')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        _runReconciliation(parsed);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading statement: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _loadSampleBankStatement() {
    const sampleCsv = '''Date,Description,Amount,Currency
2026-03-15,Adobe Creative Cloud,59.99,USD
2026-03-14,Uber Trip San Francisco,28.50,USD
2026-03-12,Blue Bottle Coffee Co,6.75,USD
2026-03-10,GitHub Copilot Enterprise,21.00,USD
2026-03-08,Whole Foods Market,84.20,USD''';

    final parsed = StatementParser.parseCsv(sampleCsv);
    _runReconciliation(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    final matchedCount = _matches.where((m) => m.isMatched).length;
    final totalCount = _matches.length;
    final matchPercentage = totalCount > 0 ? ((matchedCount / totalCount) * 100).round() : 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Bank Reconciliation',
          style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import Bank Statement (CSV/OFX)',
            onPressed: _pickStatementFile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _matches.isEmpty
              ? _buildEmptyState(context, fgCol, muted)
              : Column(
                  children: [
                    // Summary Banner
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outline),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Air-Gapped Local Matching',
                                style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$matchedCount / $totalCount Reconciled ($matchPercentage%)',
                                style: GoogleFonts.jetBrainsMono(fontSize: 16, fontWeight: FontWeight.bold, color: fgCol),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: matchPercentage >= 80 ? const Color(0xFF10B981).withOpacity(0.15) : AppColors.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              matchPercentage >= 80 ? 'HIGH PARITY 🟢' : 'PARITY READY 🟡',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: matchPercentage >= 80 ? const Color(0xFF10B981) : AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Matches List
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _matches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final match = _matches[index];
                          final trn = match.transaction;
                          final receipt = match.matchedReceipt;
                          final isMatched = match.isMatched;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isMatched ? const Color(0xFF10B981).withOpacity(0.4) : colorScheme.outline,
                                width: isMatched ? 1.2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            trn.description,
                                            style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: fgCol),
                                          ),
                                          Text(
                                            DateFormat('dd MMM yyyy').format(trn.date),
                                            style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '-\$ ${trn.amount.toStringAsFixed(2)}',
                                      style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: fgCol),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (isMatched && receipt != null) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.receipt_long, size: 14, color: Color(0xFF10B981)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Matched: ${receipt.merchantName}',
                                            style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF10B981)),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${(match.confidenceScore * 100).round()}% MATCH',
                                          style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                        ),
                                      ),
                                    ] else ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                                          const SizedBox(width: 6),
                                          Text(
                                            'No matching receipt found',
                                            style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.amber),
                                          ),
                                        ],
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Placeholder created for "${trn.description}". Scan receipt to link!')),
                                          );
                                        },
                                        child: Text('+ Add Receipt', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Color fgCol, Color muted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_outlined, color: AppColors.accent, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Zero-Cloud Bank Statement Reconciler',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Import your monthly bank or credit card statements (CSV or OFX/QBO). tAIdy matches transactions against your scanned receipts on-device with zero cloud telemetry or third-party bank logins.',
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _pickStatementFile,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text('Import Bank Statement', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: fgCol,
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loadSampleBankStatement,
              child: Text('Load Demo Bank Feed', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
