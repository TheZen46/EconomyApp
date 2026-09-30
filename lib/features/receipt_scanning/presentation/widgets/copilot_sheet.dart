import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../../../core/financial/tax_shield_provider.dart';
import '../../../../core/financial/mileage_engine.dart';
import '../../../../core/services/financial_copilot_service.dart';
import '../providers/receipt_provider.dart';

/// Opens the on-device Natural Language Copilot modal.
void showFinancialCopilotModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const CopilotSheet(),
  );
}

/// Interactive Natural Language Copilot dialog sheet.
class CopilotSheet extends ConsumerStatefulWidget {
  const CopilotSheet({super.key});

  @override
  ConsumerState<CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends ConsumerState<CopilotSheet> {
  final _queryController = TextEditingController();
  CopilotAnswer? _currentAnswer;

  final List<String> _quickPrompts = [
    'How much can I safely spend?',
    'Do I have any unpaid invoices?',
    'What is my total travel mileage deduction?',
    'Where did I spend the most money?',
  ];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _runQuery(String query) {
    if (query.trim().isEmpty) return;

    final receiptsAsync = ref.read(receiptListProvider);
    final receipts = receiptsAsync.valueOrNull ?? [];
    final invoices = ref.read(invoicesProvider);
    final boxes = ref.read(boxesProvider);
    final mileage = ref.read(mileageTripsProvider);
    final taxCalc = ref.read(taxShieldCalculationProvider);

    final answer = FinancialCopilotService.answerQuery(
      query: query,
      receipts: receipts,
      invoices: invoices,
      boxes: boxes,
      mileageTrips: mileage,
      taxCalculation: taxCalc,
    );

    setState(() {
      _currentAnswer = answer;
      _queryController.text = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Ask tAIdy Financial Copilot',
                    style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Input field
          TextField(
            controller: _queryController,
            onSubmitted: _runQuery,
            decoration: InputDecoration(
              hintText: 'Ask any financial question (e.g. "What can I spend?")...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _runQuery(_queryController.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // Quick Prompt Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickPrompts.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(p, style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                    onPressed: () => _runQuery(p),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Answer Card
          if (_currentAnswer != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _currentAnswer!.intent.name.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentAnswer!.headline,
                    style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currentAnswer!.detailedExplanation,
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                  if (_currentAnswer!.suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _currentAnswer!.suggestions.map((s) {
                        return Chip(
                          label: Text(s, style: GoogleFonts.spaceGrotesk(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
