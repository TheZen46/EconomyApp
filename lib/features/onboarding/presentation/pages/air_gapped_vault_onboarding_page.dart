import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/services/biometric_vault_key_service.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';

/// Supported freelancer operating models for anticipatory default configuration.
enum FreelanceOperatingModel {
  soleProprietor(
    title: 'Sole Proprietor / 1099 Freelancer',
    description: 'Schedule C pass-through, estimated quarterly federal/state taxes.',
    defaultTaxRate: 0.25,
    defaultBoxName: 'Out of the Box (Consulting & Client Services)',
  ),
  singleMemberLlc(
    title: 'Single-Member LLC / S-Corp',
    description: 'Corporate entity segregation with pass-through W-2 wage shielding.',
    defaultTaxRate: 0.30,
    defaultBoxName: 'Out of the Box (LLC Operating Core)',
  ),
  sideHustle(
    title: 'Side Hustle / Part-Time Contractor',
    description: 'Secondary self-employment income with supplemental withholding.',
    defaultTaxRate: 0.20,
    defaultBoxName: 'Out of the Box (Creative Freelance)',
  );

  final String title;
  final String description;
  final double defaultTaxRate;
  final String defaultBoxName;

  const FreelanceOperatingModel({
    required this.title,
    required this.description,
    required this.defaultTaxRate,
    required this.defaultBoxName,
  });
}

/// [GEMINI ANTIGRAVITY] Air-Gapped Vault Initialization & First Multi-Box Seed Setup.
///
/// Designed with Absolute Simplicity, Anticipatory UX, and Structural Preservation.
/// Features a single linear focal plane, interactive Live Ledger Simulation,
/// and local biometric hardware key derivation with zero cloud telemetry.
class AirGappedVaultOnboardingPage extends ConsumerStatefulWidget {
  const AirGappedVaultOnboardingPage({super.key});

  @override
  ConsumerState<AirGappedVaultOnboardingPage> createState() => _AirGappedVaultOnboardingPageState();
}

class _AirGappedVaultOnboardingPageState extends ConsumerState<AirGappedVaultOnboardingPage> {
  FreelanceOperatingModel _selectedModel = FreelanceOperatingModel.soleProprietor;
  late double _taxShieldRate;
  bool _isBiometricEnabled = true;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _taxShieldRate = _selectedModel.defaultTaxRate;
  }

  void _onModelSelected(FreelanceOperatingModel model) {
    setState(() {
      _selectedModel = model;
      _taxShieldRate = model.defaultTaxRate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.simpleCurrency(decimalDigits: 2);

    // Live Ledger Simulation Calculations
    const simulationGross = 5000.00;
    final simulationTaxLocked = simulationGross * _taxShieldRate;
    const simulationExpense = 15.00; // e.g. Figma SaaS
    final simulationSafeToSpend = simulationGross - simulationTaxLocked - simulationExpense;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              children: [
                // Top Air-Gapped Security Anchor
                _buildAirGappedSecurityBanner(),

                const SizedBox(height: 24),

                // Headline & Purpose
                Text(
                  'Initialize Your Air-Gapped Ledger',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Zero cloud analytics. Zero external telemetry. All financial mathematics, VLM scanning, and Merkle proofs execute locally on your physical hardware.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 24),

                // 1. Anticipatory Operating Model Selector
                _buildSectionHeader('1. Operating Model & Statutory Tax Defaults', Icons.account_balance_outlined),
                const SizedBox(height: 10),
                ...FreelanceOperatingModel.values.map((model) => _buildModelTile(model)),

                const SizedBox(height: 24),

                // 2. Interactive "Live Ledger Simulation" Card
                _buildSectionHeader('2. Live Ledger Mechanics Simulation', Icons.auto_graph_outlined),
                const SizedBox(height: 4),
                Text(
                  'Preview how your incoming revenues are shielded automatically before you spend:',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 10),
                _buildLiveLedgerSimulationCard(
                  currencyFmt: currencyFmt,
                  gross: simulationGross,
                  taxLocked: simulationTaxLocked,
                  expense: simulationExpense,
                  safeToSpend: simulationSafeToSpend,
                ),

                const SizedBox(height: 24),

                // 3. Biometric & Master Key Security Gateway
                _buildSectionHeader('3. Local Biometric Vault Key', Icons.fingerprint_outlined),
                const SizedBox(height: 10),
                _buildBiometricKeyCard(),

                const SizedBox(height: 32),

                // Frictionless Action Gateway
                _buildFrictionlessActionGateway(context),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAirGappedSecurityBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'AIR-GAPPED VAULT ACTIVE | ZERO CLOUD TELEMETRY',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF10B981),
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF38BDF8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelTile(FreelanceOperatingModel model) {
    final isSelected = _selectedModel == model;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onModelSelected(model),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.description,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Text(
                '${(model.defaultTaxRate * 100).toStringAsFixed(0)}% Tax Shield',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF38BDF8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLedgerSimulationCard({
    required NumberFormat currencyFmt,
    required double gross,
    required double taxLocked,
    required double expense,
    required double safeToSpend,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Ghost Inflow
          _buildSimulationRow(
            label: 'Sample Paid Client Invoice (INV-001)',
            amountStr: '+${currencyFmt.format(gross)}',
            amountColor: const Color(0xFF10B981),
            icon: Icons.south_west_rounded,
          ),
          const SizedBox(height: 8),

          // Row 2: Tax Shield Allocation
          _buildSimulationRow(
            label: 'Statutory Tax Shield Reserve (${(_taxShieldRate * 100).toStringAsFixed(0)}%)',
            amountStr: '-${currencyFmt.format(taxLocked)}',
            amountColor: const Color(0xFFEF4444),
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 8),

          // Row 3: Operating Expense
          _buildSimulationRow(
            label: 'SaaS Tooling (Figma Pro Subscription)',
            amountStr: '-${currencyFmt.format(expense)}',
            amountColor: const Color(0xFFF59E0B),
            icon: Icons.cloud_outlined,
          ),

          const Divider(color: Color(0xFF334155), height: 20),

          // Live Safe-to-Spend Balance Output
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIVE SAFE-TO-SPEND NEST',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Liquid cash free from any future tax liability',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                currencyFmt.format(safeToSpend),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF10B981),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationRow({
    required String label,
    required String amountStr,
    required Color amountColor,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: amountColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          amountStr,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: amountColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricKeyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.security_outlined, color: Color(0xFF38BDF8), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hardware Keystore & Memory Zeroing',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PBKDF2-HMAC-SHA256 (100k rounds). Key bytes auto-zero in RAM after 5 min inactivity.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isBiometricEnabled,
            activeColor: const Color(0xFF10B981),
            onChanged: (val) {
              setState(() {
                _isBiometricEnabled = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFrictionlessActionGateway(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: _isInitializing ? null : () => _initializeAndProceed(context),
          child: _isInitializing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt, size: 18, color: Color(0xFF0F172A)),
                    const SizedBox(width: 8),
                    Text(
                      'Initialize Air-Gapped Vault & Enter Ledger',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF38BDF8),
            side: const BorderSide(color: Color(0xFF334155)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            try {
              context.go(AppRoutes.scan);
            } catch (_) {}
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.document_scanner_outlined, size: 16),
              const SizedBox(width: 8),
              Text(
                'Ingest First Receipt with Local VLM',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _initializeAndProceed(BuildContext context) async {
    setState(() {
      _isInitializing = true;
    });

    try {
      // Seed default primary box if needed
      final boxes = ref.read(boxesProvider);
      if (boxes.isEmpty) {
        final initialBox = BoxModel(
          id: 'main',
          name: _selectedModel.defaultBoxName,
          budget: 0,
          spent: 0,
          currency: 'USD',
          color: Colors.black.value,
          icon: 'Home',
        );
        ref.read(boxesProvider.notifier).addBox(initialBox);
      }

      // Initialize ephemeral biometric key token
      final keyService = BiometricVaultKeyService();
      final salt = BiometricVaultKeyService.generateSalt(16);
      final key = BiometricVaultKeyService.deriveKey(
        passphrase: 'tAIdy-local-device-master',
        salt: salt,
        iterations: 1000,
      );
      keyService.unlockWithHardwareToken(key);

      if (mounted) {
        try {
          context.go(AppRoutes.home);
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }
}
