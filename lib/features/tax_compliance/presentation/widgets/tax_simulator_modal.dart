import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:t_aidy/core/constants/app_constants.dart';
import 'package:t_aidy/core/financial/tax_shield_provider.dart';
import 'package:t_aidy/features/tax_compliance/domain/tax_simulator_engine.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

/// Modal dialog for simulating what-if expense scenarios and their real-time tax savings.
void showTaxSimulatorModal(BuildContext context, TaxShieldCalculation taxState) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _TaxSimulatorContent(taxState: taxState),
  );
}

class _TaxSimulatorContent extends ConsumerStatefulWidget {
  final TaxShieldCalculation taxState;

  const _TaxSimulatorContent({required this.taxState});

  @override
  ConsumerState<_TaxSimulatorContent> createState() => _TaxSimulatorContentState();
}

class _TaxSimulatorContentState extends ConsumerState<_TaxSimulatorContent> {
  double _simulatedAmount = 1200.0;
  bool _isDeductible = true;
  bool _isSection179 = true;
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _simulatedAmount.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPrivacy = ref.watch(privacyModeProvider);

    final sim = TaxSimulatorEngine.simulateExpense(
      currentTaxState: widget.taxState,
      amount: _simulatedAmount,
      isDeductible: _isDeductible,
      isSection179: _isSection179,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.calculate_outlined, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'What-If Expense Simulator',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'See the net post-tax out-of-pocket cost and tax savings before you buy.',
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Amount Slider & Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(100),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outline.withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PURCHASE AMOUNT',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      AppConstants.privacyMask('\$${_simulatedAmount.toStringAsFixed(0)}', isPrivacy: isPrivacy),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _simulatedAmount.clamp(50.0, 10000.0),
                  min: 50.0,
                  max: 10000.0,
                  divisions: 199,
                  activeColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() {
                      _simulatedAmount = val;
                      _textController.text = val.toStringAsFixed(0);
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Toggles
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  selected: _isDeductible,
                  label: const Text('Business Deductible'),
                  onSelected: (val) => setState(() => _isDeductible = val),
                  avatar: Icon(_isDeductible ? Icons.check_circle : Icons.circle_outlined, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilterChip(
                  selected: _isSection179,
                  label: const Text('Sec 179 Eligible'),
                  onSelected: (val) => setState(() => _isSection179 = val),
                  avatar: Icon(_isSection179 ? Icons.bolt : Icons.bolt_outlined, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Simulation Impact Matrix
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withOpacity(0.4),
                  colorScheme.secondaryContainer.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRUE OUT-OF-POCKET COST',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppConstants.privacyMask('\$${sim.netOutOfPocketCost.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'TAX DISCOUNT',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          Text(
                            '${sim.effectiveDiscountPercent.toStringAsFixed(0)}% OFF',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Direct Tax Savings', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          Text(
                            '+' + AppConstants.privacyMask('\$${sim.directTaxSavings.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                            style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Updated Safe-to-Spend', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          Text(
                            AppConstants.privacyMask('\$${sim.newSafeToSpend.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                            style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text('Got It', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

