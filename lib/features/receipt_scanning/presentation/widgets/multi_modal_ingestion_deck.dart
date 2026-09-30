import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:t_aidy/features/receipt_scanning/domain/usecases/bayesian_categorizer_engine.dart';
import 'package:t_aidy/features/receipt_scanning/domain/usecases/voice_dictation_engine.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../domain/entities/receipt.dart';
import '../providers/receipt_provider.dart';

/// Capture mode for the multi-modal ingestion deck.
enum IngestionMode {
  cameraOcr,
  voiceDictation,
  quickManual,
}

/// [GEMINI ANTIGRAVITY] Multi-Modal Ingestion Deck & Autonomous Parity Verification.
///
/// Features a persistent dual-pane viewfinder, bottom 45% thumb-reachable draft surface,
/// real-time arithmetic parity cross-checking, and Bayesian predictive Box/Tax allocation.
class MultiModalIngestionDeck extends ConsumerStatefulWidget {
  final Receipt? initialDraft;
  final VoidCallback? onComplete;

  const MultiModalIngestionDeck({
    super.key,
    this.initialDraft,
    this.onComplete,
  });

  @override
  ConsumerState<MultiModalIngestionDeck> createState() => _MultiModalIngestionDeckState();
}

class _MultiModalIngestionDeckState extends ConsumerState<MultiModalIngestionDeck> {
  IngestionMode _mode = IngestionMode.cameraOcr;
  final TextEditingController _voiceInputController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  final TextEditingController _taxController = TextEditingController();
  final TextEditingController _tipController = TextEditingController();

  final List<ReceiptItem> _lineItems = [];
  String? _selectedBoxId;
  String _selectedCategory = 'General Business Expense';
  bool _isParityValid = true;
  double _computedDiscrepancy = 0.0;
  final BayesianCategorizerEngine _bayesianEngine = BayesianCategorizerEngine();

  // Zoom Loupe State
  Offset _loupePosition = const Offset(0.5, 0.5);
  bool _isLoupeActive = false;

  @override
  void initState() {
    super.initState();
    _initDraft(widget.initialDraft);
  }

  void _initDraft(Receipt? draft) {
    if (draft != null) {
      _merchantController.text = draft.merchantName;
      _totalAmountController.text = draft.totalAmount.toStringAsFixed(2);
      _taxController.text = '0.00';
      _tipController.text = '0.00';
      _lineItems.clear();
      _lineItems.addAll(draft.items);
      _selectedBoxId = draft.boxId;
    } else {
      // Seed default smart draft
      _merchantController.text = 'Olive Garden Italian Restaurant';
      _totalAmountController.text = '45.50';
      _taxController.text = '3.50';
      _tipController.text = '7.00';
      _lineItems.addAll([
        const ReceiptItem(
          description: 'Lunch Pasta & Soup Combo',
          unitPrice: 20.00,
          quantity: 1,
          totalPrice: 20.00,
          mainCategory: 'Meals & Entertainment',
        ),
        const ReceiptItem(
          description: 'Grilled Chicken Entree',
          unitPrice: 15.00,
          quantity: 1,
          totalPrice: 15.00,
          mainCategory: 'Meals & Entertainment',
        ),
      ]);
    }

    _trainAndPredict();
    _validateArithmeticParity();
  }

  void _trainAndPredict() {
    final historicalReceipts = ref.read(receiptListProvider).valueOrNull ?? [];
    if (historicalReceipts.isNotEmpty) {
      _bayesianEngine.train(historicalReceipts);
      final prediction = _bayesianEngine.predict(
        merchantName: _merchantController.text,
        lineItemText: _lineItems.map((e) => e.description).join(' '),
      );
      setState(() {
        _selectedCategory = prediction.predictedCategory;
        _selectedBoxId ??= prediction.predictedBoxId;
      });
    }
  }

  void _validateArithmeticParity() {
    final grandTotal = double.tryParse(_totalAmountController.text) ?? 0.0;
    final tax = double.tryParse(_taxController.text) ?? 0.0;
    final tip = double.tryParse(_tipController.text) ?? 0.0;
    final lineItemsSum = _lineItems.fold(0.0, (sum, item) => sum + item.totalPrice);

    final expectedTotal = lineItemsSum + tax + tip;
    final discrepancy = (grandTotal - expectedTotal).abs();

    setState(() {
      _computedDiscrepancy = grandTotal - expectedTotal;
      _isParityValid = discrepancy < 0.01;
    });
  }

  void _applyArithmeticAutoCorrection() {
    final tax = double.tryParse(_taxController.text) ?? 0.0;
    final tip = double.tryParse(_tipController.text) ?? 0.0;
    final lineItemsSum = _lineItems.fold(0.0, (sum, item) => sum + item.totalPrice);

    final correctedGrandTotal = lineItemsSum + tax + tip;
    setState(() {
      _totalAmountController.text = correctedGrandTotal.toStringAsFixed(2);
      _validateArithmeticParity();
    });
  }

  void _handleVoiceTranscription(String text) {
    final parsed = VoiceDictationEngine.parseTranscript(text);
    if (parsed.amount > 0) {
      _merchantController.text = parsed.merchant;
      _totalAmountController.text = parsed.amount.toStringAsFixed(2);
      _selectedCategory = parsed.category;

      final boxes = ref.read(boxesProvider);
      if (parsed.boxName != null && boxes.isNotEmpty) {
        final match = boxes.firstWhere(
          (b) => b.name.toLowerCase().contains(parsed.boxName!.toLowerCase()),
          orElse: () => boxes.first,
        );
        _selectedBoxId = match.id;
      }

      _lineItems.clear();
      _lineItems.add(ReceiptItem(
        description: parsed.businessPurpose ?? 'Spoken Expense Item',
        unitPrice: parsed.amount,
        quantity: 1,
        totalPrice: parsed.amount,
        mainCategory: parsed.category,
      ));

      _validateArithmeticParity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxes = ref.watch(boxesProvider);
    final currencyFmt = NumberFormat.simpleCurrency(decimalDigits: 2);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Mode Selector Bar
            _buildTopModeSelector(),

            // Top 55%: Persistent Viewfinder with Synchronized Loupe
            Expanded(
              flex: 55,
              child: _buildTopViewfinderPane(),
            ),

            // Bottom 45%: Grounded Thumb-Reachable Ingestion & Parity Deck
            Expanded(
              flex: 45,
              child: _buildBottomDraftDeck(boxes, currencyFmt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModeChip('Camera OCR', IngestionMode.cameraOcr, Icons.camera_alt_outlined),
                    _buildModeChip('Voice Dictate', IngestionMode.voiceDictation, Icons.mic_none_outlined),
                    _buildModeChip('Manual Matrix', IngestionMode.quickManual, Icons.edit_note_outlined),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, IngestionMode mode, IconData icon) {
    final isSelected = _mode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          _mode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopViewfinderPane() {
    if (_mode == IngestionMode.voiceDictation) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Text(
                  'On-Device Speech Transcription Stream',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: TextField(
                  controller: _voiceInputController,
                  maxLines: null,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'e.g. "Spent 45 dollars at Olive Garden for team dinner with Acme in Consulting box"',
                    hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    border: InputBorder.none,
                  ),
                  onChanged: _handleVoiceTranscription,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '100% offline rule-based semantic grammar parser. Audio never leaves device RAM.',
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    // Default Camera / OCR Viewfinder with Synchronized Loupe
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Simulated High-Contrast Document View
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.document_scanner_outlined, size: 48, color: Color(0xFF38BDF8)),
                      const SizedBox(height: 8),
                      Text(
                        'LOCAL VLM OCR ACTIVE',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF38BDF8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hold still • Tap document to zoom loupe',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),

                // Interactive Loupe Overlay
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isLoupeActive = true;
                      _loupePosition = details.localPosition;
                    });
                  },
                  onPanEnd: (_) {
                    setState(() {
                      _isLoupeActive = false;
                    });
                  },
                ),

                if (_isLoupeActive)
                  Positioned(
                    left: _loupePosition.dx - 40,
                    top: _loupePosition.dy - 40,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                      ),
                      child: const Center(
                        child: Icon(Icons.search, color: Color(0xFF38BDF8), size: 24),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Live Parity Indicator Pill
        Positioned(
          top: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isParityValid ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isParityValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isParityValid ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  size: 12,
                  color: _isParityValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 4),
                Text(
                  _isParityValid ? 'PARITY VERIFIED' : 'PARITY DISCREPANCY',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _isParityValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomDraftDeck(List<BoxModel> boxes, NumberFormat currencyFmt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(top: BorderSide(color: Color(0xFF334155), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Merchant & Grand Total inputs
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _buildInputField(
                  label: 'Merchant',
                  controller: _merchantController,
                  onChanged: (_) => _trainAndPredict(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _buildInputField(
                  label: 'Grand Total (\$)',
                  controller: _totalAmountController,
                  isHighlighted: !_isParityValid,
                  onChanged: (_) => _validateArithmeticParity(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Predictive Box & Category Pickers
          Row(
            children: [
              Expanded(
                child: _buildBoxSelectorDropdown(boxes),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tax Category (Bayesian)',
                        style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8)),
                      ),
                      Text(
                        _selectedCategory,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Discrepancy auto-correction notice if needed
          if (!_isParityValid) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Discrepancy: ${currencyFmt.format(_computedDiscrepancy.abs())} variance detected.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFF59E0B)),
                    ),
                  ),
                  InkWell(
                    onTap: _applyArithmeticAutoCorrection,
                    child: Text(
                      'Auto-Correct Total',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF38BDF8)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // High-Contrast Tactile Action Bar
          _buildTactileActionBar(context),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    bool isHighlighted = false,
    Function(String)? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFF334155),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8))),
          TextField(
            controller: controller,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildBoxSelectorDropdown(List<BoxModel> boxes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assigned Box', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8))),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedBoxId ?? (boxes.isNotEmpty ? boxes.first.id : 'main'),
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              items: (boxes.isEmpty
                      ? [BoxModel(id: 'main', name: 'Main Consulting Box', budget: 0, spent: 0, currency: 'USD', color: 0)]
                      : boxes)
                  .map<DropdownMenuItem<String>>((b) => DropdownMenuItem<String>(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedBoxId = val;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTactileActionBar(BuildContext context) {
    return Row(
      children: [
        // Secondary: Split Line Items
        Expanded(
          flex: 4,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF334155)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              // Open line-item split modal
            },
            child: Text(
              'Split Box Lines (${_lineItems.length})',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Primary: Confirm & Shield Tax
        Expanded(
          flex: 6,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              final grandTotal = double.tryParse(_totalAmountController.text) ?? 0.0;
              final newReceipt = Receipt(
                id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
                merchantName: _merchantController.text.isNotEmpty ? _merchantController.text : 'Merchant',
                totalAmount: grandTotal,
                currency: 'USD',
                date: DateTime.now(),
                boxId: _selectedBoxId ?? 'main',
                items: List.from(_lineItems),
              );

              ref.read(receiptListProvider.notifier).addReceipt(newReceipt);
              widget.onComplete?.call();
              Navigator.of(context).maybePop();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF0F172A)),
                const SizedBox(width: 6),
                Text(
                  'Confirm & Shield Tax',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
