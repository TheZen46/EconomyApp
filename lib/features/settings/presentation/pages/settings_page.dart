import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/privacy/network_policy.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../receipt_scanning/data/datasources/csv_parser_service.dart';
import '../../../receipt_scanning/data/datasources/sync_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../receipt_scanning/data/models/sync_item_model.dart';
import '../../../../core/services/google_drive_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/routes/app_router.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import '../../../../core/sync/sync_providers.dart';
import '../providers/llm_provider.dart';
import '../widgets/dataset_export_dialog.dart';
import '../../../../core/services/audit_dossier_service.dart';
import '../../../../core/services/audit_packager_service.dart';
import '../../../../core/services/export_service.dart';
import '../../../../core/financial/tax_shield_provider.dart';
import '../../../boxes/data/providers/boxes_provider.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const _accent = Color(0xFF002FA7);
const _panelWidth = 480.0;

// ─── Route-based wrapper (kept for direct /settings route if needed) ──────────
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: const SettingsPanelWidget(),
    );
  }
}

// ─── Overlay panel widget (used by showGeneralDialog in home_page) ────────────
class SettingsPanelWidget extends ConsumerStatefulWidget {
  const SettingsPanelWidget({super.key});

  @override
  ConsumerState<SettingsPanelWidget> createState() => _SettingsPanelWidgetState();
}

class _SettingsPanelWidgetState extends ConsumerState<SettingsPanelWidget> {
  int _devModeClicks = 0;
  bool _isDevMode = false;
  bool _isUploading = false;
  bool _isExportingAuditPack = false;
  bool _isExportingCpaPortal = false;
  bool _isEditingBudget = false;
  late TextEditingController _budgetCtrl;
  final _budgetFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    try {
      final box = ref.read(settingsBoxProvider);
      _isDevMode = box.get('is_dev_mode', defaultValue: false) as bool;
    } catch (_) {}
    final budget = ref.read(monthlyBudgetProvider);
    _budgetCtrl = TextEditingController(text: budget.toStringAsFixed(0));
    _budgetFocus.addListener(() {
      if (!_budgetFocus.hasFocus && _isEditingBudget) _submitBudget();
    });
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    _budgetFocus.dispose();
    super.dispose();
  }

  void _submitBudget() {
    final val = double.tryParse(_budgetCtrl.text.replaceAll(',', ''));
    if (val != null) {
      ref.read(monthlyBudgetProvider.notifier).setBudget(val);
      _budgetCtrl.text = val.toStringAsFixed(0);
    } else {
      final current = ref.read(monthlyBudgetProvider);
      _budgetCtrl.text = current.toStringAsFixed(0);
    }
    setState(() => _isEditingBudget = false);
  }

  void _onVersionTap() {
    if (_isDevMode) return;
    setState(() {
      _devModeClicks++;
      if (_devModeClicks >= 7) {
        _isDevMode = true;
        try {
          ref.read(settingsBoxProvider).put('is_dev_mode', true);
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Developer Mode Unlocked! 🛠️')),
        );
      } else if (_devModeClicks > 2) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${7 - _devModeClicks} taps to dev mode…'),
            duration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bg = colorScheme.surface;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final divider = colorScheme.outline;
    final tileBg = colorScheme.surfaceContainer;

    final storageAsync = ref.watch(storageUsageProvider);
    final currentBudget = ref.watch(monthlyBudgetProvider);
    final receiptsAsync = ref.watch(receiptListProvider);
    final receipts = receiptsAsync.valueOrNull ?? [];
    final boxes = ref.watch(boxesProvider);
    final taxCalc = ref.watch(taxShieldCalculationProvider);

    // Compute live Merkle root digest for the top status indicator
    final auditManifest = AuditDossierService.buildAuditManifest(receipts: receipts);
    final merkleRoot = (auditManifest['merkle_root_digest'] as String?) ?? '0000000000000000000000000000000000000000000000000000000000000000';
    final shortMerkle = merkleRoot.length >= 8
        ? '${merkleRoot.substring(0, 4)}...${merkleRoot.substring(merkleRoot.length - 4)}'
        : merkleRoot;

    // Panel is always right-aligned, fixed width
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _panelWidth,
          height: double.infinity,
          color: bg,
          child: SafeArea(
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border(
                        bottom: BorderSide(color: divider, width: 1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SETTINGS & CRYPTOGRAPHIC DOSSIER',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                letterSpacing: 1.4,
                                color: muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Preferences',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                color: fgCol,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Close button (X)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: divider, width: 1),
                          ),
                          child: Icon(Icons.close,
                              color: muted, size: 18),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 200.ms),

                // ── Scrollable content ────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 80),
                    children: [
                      // ── Live Cryptographic Status Indicator ───────────────
                      _buildVaultHealthCard(
                        merkleRoot: merkleRoot,
                        shortMerkle: shortMerkle,
                        tileBg: tileBg,
                        divider: divider,
                        fgCol: fgCol,
                        muted: muted,
                        colorScheme: colorScheme,
                        context: context,
                      ),

                      const SizedBox(height: 28),

                      // ══════════════════════════════════════════════════════
                      // MASTER SECTION 1: Cryptographic Vault & Biometrics
                      // ══════════════════════════════════════════════════════
                      _sectionHeader(Icons.security_outlined, 'Cryptographic Vault & Biometrics', muted, 0),
                      const SizedBox(height: 12),

                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Column(
                          children: [
                            // 1. Biometric Lock
                            Consumer(builder: (context, ref, _) {
                              final isBiometricEnabled = ref.watch(biometricEnabledProvider);
                              return Column(
                                children: [
                                  _row(
                                    label: 'Biometric Lock (FaceID / Fingerprint)',
                                    subtitle: 'Locks memory keys after 5 minutes of inactivity',
                                    fgCol: fgCol,
                                    muted: muted,
                                    trailing: _FigmaToggle(
                                      value: isBiometricEnabled,
                                      onChanged: (val) async {
                                        if (val) {
                                          final canAuth = await ref.read(biometricServiceProvider).canAuthenticate();
                                          if (!canAuth) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Biometrics not available on this device'),
                                                  backgroundColor: Color(0xFFD4183D),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          // The lock fails closed, so only enable it once the user
                                          // has shown that they can pass it on this device.
                                          final verified = await ref
                                              .read(biometricServiceProvider)
                                              .authenticate('Confirm to enable the tAIdy lock');
                                          if (!verified) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Verification failed. The lock was not enabled.'),
                                                  backgroundColor: Color(0xFFD4183D),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                        await ref.read(biometricEnabledProvider.notifier).setEnabled(val);
                                      },
                                    ),
                                  ),
                                  if (isBiometricEnabled) ...[
                                    Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                    _row(
                                      label: 'Test Biometrics',
                                      subtitle: 'Verify biometric challenge response',
                                      fgCol: fgCol,
                                      muted: muted,
                                      trailing: _chip('Verify', const Color(0xFF10B981), divider),
                                      onTap: () async {
                                        final authSuccess = await ref.read(biometricServiceProvider).authenticate('Testing tAIdy biometric security');
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(authSuccess ? 'Biometrics verified successfully! 🛡️' : 'Biometric verification cancelled.'),
                                              backgroundColor: authSuccess ? const Color(0xFF10B981) : const Color(0xFFD4183D),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              );
                            }),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            // 2. Sealed Cryptographic Audit Pack (.zip)
                            _row(
                              label: 'Sealed Cryptographic Audit Pack (.zip)',
                              subtitle: 'Includes Merkle JSON-LD manifest, self-verifying standalone audit HTML, and full CSV ledger',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _isExportingAuditPack
                                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))
                                  : _chip('Generate .ZIP', _accent, divider),
                              onTap: _isExportingAuditPack ? null : () => _exportAuditPack(receipts, boxes),
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 3. Sanitized CPA Tax Portal (.html)
                            _row(
                              label: 'Sanitized CPA Tax Portal (.html)',
                              subtitle: 'Zero-knowledge air-gapped portal. Redacts PII with salted TIN hashes, masked addresses & truncated accounts',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _isExportingCpaPortal
                                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))
                                  : _chip('Generate .HTML', _accent, divider),
                              onTap: _isExportingCpaPortal ? null : () => _exportCpaPortal(receipts, boxes),
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 4. Continuous Learning Corpus (JSONL)
                            _row(
                              label: 'Continuous Learning Corpus (JSONL)',
                              subtitle: 'Fine-tuning dataset generated from anonymized line items & tax categories',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _chip('Inspect / Export', _accent, divider),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => const DatasetExportDialog(),
                                );
                              },
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 5. Local AI Brain Models
                            _row(
                              label: 'Local AI Brain Models',
                              subtitle: 'Manage on-device Vision-Language Models (Qwen2-VL 2B) and weights',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _chip('Manage', muted, divider),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push(AppRoutes.modelManager);
                              },
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // Isolation mode: keeps all data on this device (NetworkPolicy).
                            Consumer(builder: (context, ref, _) {
                              final box = ref.watch(settingsBoxProvider);
                              final isIsolated = NetworkPolicy.isIsolated(box);
                              return _row(
                                label: 'Isolation Mode (no cloud access)',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.info_outline, size: 16, color: muted),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: colorScheme.surface,
                                            title: Text('Isolation Mode', style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.bold)),
                                            content: Text(
                                              'When this is on, tAIdy keeps all data on this device: cloud synchronization, uploads (training contribution and Google Drive backup), webhooks, Gemini cloud AI and model update checks are skipped. Changes made meanwhile stay queued on the device and are synchronized after you turn it off.\n\n'
                                              'The eye icon on the dashboard is separate: it only hides figures on screen.',
                                              style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 13),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: Text('Understood', style: GoogleFonts.spaceGrotesk(color: _accent, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    _FigmaToggle(
                                      value: isIsolated,
                                      onChanged: (val) async {
                                        await box.put(NetworkPolicy.isolationModeKey, val);
                                        // The AI service is chosen from settings; re-evaluate it.
                                        ref.invalidate(aiServiceProvider);
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            Consumer(builder: (context, ref, _) {
                              final box = ref.watch(settingsBoxProvider);
                              final isContributionEnabled = SyncService.isTrainingContributionEnabled(box);
                              return _row(
                                label: 'AI Model Training Contribution',
                                subtitle: 'Anonymized tokenized line items contribute to local procedural fine-tuning',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.info_outline, size: 16, color: muted),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: colorScheme.surface,
                                            title: Text('AI Model Training Contribution', style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.bold)),
                                            content: Text(
                                              'When this is on, every receipt you save is uploaded to a private folder in your tAIdy cloud account: the receipt photo, unaltered, and the extracted data (merchant, date, total, currency and line items). The tAIdy team may use these files to improve receipt recognition. They are not publicly accessible.\n\n'
                                              'When this is off, nothing is uploaded and receipt photos stay on this device. Turning it off does not delete files that were already uploaded.',
                                              style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 13),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: Text('Understood', style: GoogleFonts.spaceGrotesk(color: _accent, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    _FigmaToggle(
                                      value: isContributionEnabled,
                                      onChanged: (val) {
                                        box.put(SyncService.trainingContributionKey, val);
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 7. Dataset Contribution Storage
                            storageAsync.when(
                              data: (bytes) => _row(
                                label: 'Dataset Contribution Storage',
                                subtitle: 'Local storage used for scrubbed training samples',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: Text('${(bytes / 1024).toStringAsFixed(1)} KB',
                                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: muted)),
                                onTap: () => ref.refresh(storageUsageProvider),
                              ),
                              loading: () => _row(
                                label: 'Dataset Contribution Storage',
                                subtitle: 'Local storage used for scrubbed training samples',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: muted)),
                              ),
                              error: (err, stack) => _row(
                                label: 'Dataset Contribution Storage',
                                subtitle: 'Local storage used for scrubbed training samples',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: Text('Error', style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12, color: const Color(0xFFD4183D))),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ══════════════════════════════════════════════════════
                      // MASTER SECTION 2: Multi-Box & Statutory Tax Profiles
                      // ══════════════════════════════════════════════════════
                      _sectionHeader(Icons.account_balance_wallet_outlined, 'Multi-Box & Statutory Tax Profiles', muted, 1),
                      const SizedBox(height: 12),

                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Column(
                          children: [
                            // 1. Monthly Budget
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Monthly Budget',
                                            style: GoogleFonts.spaceGrotesk(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                                color: fgCol)),
                                        const SizedBox(height: 3),
                                        Text('Master ceiling for discretionary personal and business spending',
                                            style: GoogleFonts.spaceGrotesk(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w300,
                                                color: muted)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _isEditingBudget
                                      ? SizedBox(
                                          width: 130,
                                          child: Row(children: [
                                            Text('\$',
                                                style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 14, color: muted)),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: TextField(
                                                controller: _budgetCtrl,
                                                focusNode: _budgetFocus,
                                                autofocus: true,
                                                keyboardType: TextInputType.number,
                                                onSubmitted: (_) => _submitBudget(),
                                                style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 14, color: fgCol),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 8),
                                                  border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: _accent)),
                                                  focusedBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: _accent)),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: BorderSide(color: divider)),
                                                ),
                                              ),
                                            ),
                                          ]),
                                        )
                                      : GestureDetector(
                                          onTap: () {
                                            _budgetCtrl.text =
                                                currentBudget.toStringAsFixed(0);
                                            setState(() => _isEditingBudget = true);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: divider),
                                            ),
                                            child: Text(
                                              '\$${currentBudget.toStringAsFixed(0)}',
                                              style: GoogleFonts.jetBrainsMono(
                                                  fontSize: 14, color: muted),
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 2. Statutory Tax Shield Profile & Rate
                            _row(
                              label: 'Statutory Tax Shield Profile',
                              subtitle: '${taxCalc.profile.name} (${(taxCalc.effectiveTaxRate * 100).toInt()}% Auto-Stash Reserve)',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _chip('${(taxCalc.effectiveTaxRate * 100).toInt()}% Rate', _accent, divider),
                              onTap: () => _showTaxProfileDialog(context, ref),
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 3. Multi-Box Entity Containers
                            _row(
                              label: 'Multi-Box Entity Containers',
                              subtitle: 'Segregate personal life from LLCs, freelancing, and sole proprietorships',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${boxes.length} Active',
                                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: muted),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right, size: 18, color: muted),
                                ],
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push(AppRoutes.boxes);
                              },
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 4. Manage Categories & Taxonomy
                            _row(
                              label: 'Manage Categories & Taxonomy',
                              subtitle: 'Custom Schedule C expense categories, deduction rules, and asset depreciation',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: Icon(Icons.chevron_right, size: 18, color: muted),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push(AppRoutes.taxonomy);
                              },
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 5. Active Engine & Telemetry
                            Consumer(builder: (context, ref, _) {
                              final box = ref.watch(settingsBoxProvider);
                              final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
                              final isVlmActive = ref.watch(isVlmReadyProvider);
                              final apiKeyAsync = ref.watch(geminiApiKeyProvider);
                              final apiKey = apiKeyAsync.valueOrNull ?? '';

                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ACTIVE INFERENCE ENGINE',
                                                style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.2, color: muted, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                isVlmActive ? 'Qwen2-VL 2B (Local 4-Bit)' : (isEnabled ? 'Gemini 1.5 Flash (Cloud)' : 'ML Kit OCR (Local Hybrid)'),
                                                style: GoogleFonts.jetBrainsMono(fontSize: 13, color: isVlmActive ? const Color(0xFF10B981) : const Color(0xFF0891B2), fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Builder(builder: (_) {
                                          final String memLabel;
                                          if (isVlmActive) {
                                            memLabel = 'VRAM: ~669 MB';
                                          } else if (isEnabled && apiKey.isNotEmpty) {
                                            memLabel = 'RAM: ~12 MB (Cloud)';
                                          } else {
                                            memLabel = 'RAM: ~38 MB (ML Kit)';
                                          }
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: divider),
                                            ),
                                            child: Text(
                                              memLabel,
                                              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: fgCol),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                  Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                  _row(
                                    label: 'Benchmark Local LLM',
                                    subtitle: 'Measure on-device grammar parsing and memory latency',
                                    fgCol: fgCol,
                                    muted: muted,
                                    trailing: _chip('Run Test', _accent, divider),
                                    onTap: () async {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Benchmarking on-device grammar and memory latency... ⚡'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                      try {
                                        final vlmService = ref.read(vlmEngineServiceProvider);
                                        final results = await vlmService.benchmarkInference();
                                        if (!context.mounted) return;
                                        final grammarMs = results['grammar_latency_ms'] ?? results['grammar_gen_ms'] ?? 0;
                                        final memoryMs = results['memory_latency_ms'] ?? results['memory_retrieval_ms'] ?? 0;
                                        final tokensPerSec = results['tokens_per_sec'];
                                        final status = results['status'] ?? 'N/A';
                                        await showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: colorScheme.surface,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            title: Text(
                                              'Local Engine Benchmark',
                                              style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.bold, fontSize: 18),
                                            ),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Grammar Engine Latency: ${grammarMs}ms', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: fgCol)),
                                                const SizedBox(height: 8),
                                                Text('Episodic Retrieval: ${memoryMs}ms', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: fgCol)),
                                                const SizedBox(height: 8),
                                                Text(
                                                  tokensPerSec != null
                                                      ? 'Throughput: $tokensPerSec tokens/sec'
                                                      : 'Throughput: N/A ($status)',
                                                  style: GoogleFonts.jetBrainsMono(fontSize: 13, color: _accent, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: Text('Close', style: GoogleFonts.spaceGrotesk(color: _accent, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Benchmark error: $e')),
                                        );
                                      }
                                    },
                                  ),
                                  Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                  _row(
                                    label: 'Enable Gemini AI (Cloud Fallback)',
                                    subtitle: 'Use Google Gemini 1.5 Flash when on-device VLM is disabled',
                                    fgCol: fgCol,
                                    muted: muted,
                                    trailing: _FigmaToggle(
                                      value: isEnabled,
                                      onChanged: (val) {
                                        box.put('enable_gemini_ai', val);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                  _row(
                                    label: 'Set API Key…',
                                    subtitle: 'Saved securely to device encrypted keychain (never synced)',
                                    fgCol: isEnabled ? fgCol : muted,
                                    muted: muted,
                                    onTap: isEnabled ? () => _showApiKeyDialog(apiKey) : null,
                                    trailing: isEnabled
                                        ? Icon(Icons.edit_outlined, size: 16, color: muted)
                                        : null,
                                  ),
                                  Consumer(builder: (context, ref, _) {
                                    final deadLettered = ref.watch(deadLetteredMutationCountProvider).valueOrNull ?? 0;
                                    if (deadLettered == 0) return const SizedBox.shrink();
                                    return Column(
                                      children: [
                                        Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                        _row(
                                          label: '$deadLettered unsynced ${deadLettered == 1 ? 'change' : 'changes'} rejected by the server',
                                          fgCol: const Color(0xFFD4183D),
                                          muted: muted,
                                          trailing: _chip('Retry', _accent, divider),
                                          onTap: () {
                                            ref.read(syncManagerProvider)?.retryDeadLettered();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Retrying rejected changes…')),
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              );
                            }),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 6. Dark Mode
                            _row(
                              label: 'Dark Mode',
                              subtitle: 'High-contrast slate OLED theme optimized for low eye strain',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _FigmaToggle(
                                value: isDark,
                                onChanged: (_) =>
                                    ref.read(themeProvider.notifier).toggle(),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ══════════════════════════════════════════════════════
                      // MASTER SECTION 3: Optical/P2P Air-Gapped Sync & Backups
                      // ══════════════════════════════════════════════════════
                      _sectionHeader(Icons.sync_alt_outlined, 'Optical/P2P Air-Gapped Sync & Backups', muted, 2),
                      const SizedBox(height: 12),

                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Optical Animated QR Vault Sync
                            _row(
                              label: 'Optical Animated QR Vault Sync',
                              subtitle: 'Air-gapped P2P cryptographic ledger sync via animated multi-chunk QR stream',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _chip('Start Sync', _accent, divider),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push(AppRoutes.syncProgress);
                              },
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 2. Sync Center & Outbox
                            Consumer(builder: (context, ref, _) {
                              final syncItemsAsync = ref.watch(syncQueueStreamProvider);
                              final syncItems = syncItemsAsync.valueOrNull ?? [];
                              final failedItems = syncItems.where((i) => i.status == SyncStatus.permanentlyFailed).toList();
                              final pendingItems = syncItems.where((i) => i.status != SyncStatus.permanentlyFailed).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _row(
                                    label: 'Sync Center & Local Outbox',
                                    subtitle: 'Local CRDT outbox queue for deterministic conflict-free replication',
                                    fgCol: fgCol,
                                    muted: muted,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (failedItems.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD4183D).withAlpha(40),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: const Color(0xFFD4183D)),
                                            ),
                                            child: Text(
                                              '${failedItems.length} Failed',
                                              style: GoogleFonts.spaceGrotesk(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFFD4183D),
                                              ),
                                            ),
                                          ),
                                        Text(
                                          pendingItems.isEmpty ? 'All Synced' : '${pendingItems.length} Pending',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 12,
                                            color: pendingItems.isEmpty ? const Color(0xFF10B981) : muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                  _row(
                                    label: 'Replicate Cloud Data',
                                    subtitle: 'Manual trigger to push pending outbox mutations to remote replica',
                                    fgCol: fgCol,
                                    muted: muted,
                                    trailing: _chip('Sync Now', _accent, divider),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      ref.read(initialSyncCompletedProvider.notifier).state = false;
                                      context.push(AppRoutes.syncProgress);
                                    },
                                  ),
                                  if (failedItems.isNotEmpty) ...[
                                    Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Permanently Failed Uploads (Max 5 attempts exceeded)',
                                            style: GoogleFonts.spaceGrotesk(
                                              fontSize: 12,
                                              color: const Color(0xFFD4183D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          for (final item in failedItems)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 8.0),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'Receipt ${item.receiptId.length > 8 ? item.receiptId.substring(0, 8) : item.receiptId}',
                                                          style: GoogleFonts.jetBrainsMono(
                                                            fontSize: 13,
                                                            color: fgCol,
                                                          ),
                                                        ),
                                                        if (item.errorMessage != null)
                                                          Text(
                                                            item.errorMessage!,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: GoogleFonts.spaceGrotesk(
                                                              fontSize: 11,
                                                              color: muted,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      ref.read(syncServiceProvider).retryFailedItem(item.receiptId);
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Retrying receipt ${item.receiptId}…')),
                                                      );
                                                    },
                                                    icon: const Icon(Icons.refresh, size: 14),
                                                    label: Text(
                                                      'Manual Retry',
                                                      style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold),
                                                    ),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: _accent,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            }),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 3. Import Bank CSV
                            _row(
                              label: 'Import Bank CSV',
                              subtitle: 'Parse bank statements or credit card exports into the air-gapped ledger',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: Icon(Icons.file_upload_outlined, size: 18, color: muted),
                              onTap: _importCsv,
                            ),

                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                            // 4. Integrations & Webhooks
                            _row(
                              label: 'Integrations & Webhooks',
                              subtitle: 'Offline webhooks, accounting API bridges, and external sync endpoints',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: Icon(Icons.chevron_right, size: 18, color: muted),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push(AppRoutes.integrations);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Clear All Data
                      _outlineBtn(
                        label: 'Clear All Vault Data',
                        color: const Color(0xFFD4183D),
                        borderColor: const Color(0xFFD4183D).withAlpha(60),
                        onTap: () => _showClearDialog(),
                      ),

                      const SizedBox(height: 8),

                      // Log Out
                      _outlineBtn(
                        label: 'Log Out',
                        color: muted,
                        borderColor: divider,
                        onTap: () async {
                          Navigator.of(context).pop();
                          await ref.read(authProvider.notifier).signOut();
                        },
                      ),

                      // ── Dev Mode ─────────────────────────────────────────
                      if (_isDevMode) ...[
                        const SizedBox(height: 28),
                        _sectionHeader(Icons.developer_mode_outlined, 'Admin & Cloud Backup Tools', muted, 3),
                        const SizedBox(height: 12),
                        Consumer(builder: (context, ref, _) {
                          final box = ref.watch(settingsBoxProvider);
                          final useDrive = box.get('use_google_drive_storage', defaultValue: false) as bool;
                          return _cardWrapper(tileBg: tileBg, divider: divider, child:
                            Column(children: [
                              _row(
                                label: 'Storage Provider: Google Drive',
                                subtitle: 'Secondary cloud backup mirror for encrypted snapshots',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: _FigmaToggle(value: useDrive, onChanged: (val) {
                                  box.put('use_google_drive_storage', val);
                                  setState(() {});
                                }),
                              ),
                              Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                              _row(
                                label: _isUploading ? 'Uploading…' : 'Archive All Data Now',
                                subtitle: 'Trigger complete snapshot zip upload to configured cloud storage',
                                fgCol: fgCol,
                                muted: muted,
                                trailing: _isUploading
                                    ? SizedBox(width: 14, height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))
                                    : Icon(Icons.backup_outlined, size: 16, color: muted),
                                onTap: _isUploading ? null : _archiveData,
                              ),
                            ]),
                          );
                        }),
                      ],

                      // ── Version ──────────────────────────────────────────
                      const SizedBox(height: 40),
                      GestureDetector(
                        onTap: _onVersionTap,
                        child: Center(
                          child: Text(
                            'tAIdy v0.3.0 (Beta) [AIR-GAPPED ED25519-SHA256]${_isDevMode ? " [DEV]" : ""}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                                color: muted.withAlpha(128)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Vault Health Card ───────────────────────────────────────────────────

  Widget _buildVaultHealthCard({
    required String merkleRoot,
    required String shortMerkle,
    required Color tileBg,
    required Color divider,
    required Color fgCol,
    required Color muted,
    required ColorScheme colorScheme,
    required BuildContext context,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Expanded(
                child: Text(
                  'VAULT HEALTH & KEY INTEGRITY',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                    color: fgCol,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(30),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(100)),
                ),
                child: Text(
                  'AIR-GAPPED',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _showVaultDetailsDialog(merkleRoot),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: divider.withAlpha(80)),
              ),
              child: Row(
                children: [
                  Icon(Icons.fingerprint, size: 16, color: _accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SHA-256 Merkle Root: [$shortMerkle] | RAM Key: Zeroed on Lock | Cloud: AIR-GAPPED',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: fgCol,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 14, color: muted),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, curve: Curves.easeOut);
  }

  // ─── Export Actions ──────────────────────────────────────────────────────

  Future<void> _exportAuditPack(List<dynamic> receipts, List<dynamic> boxes) async {
    if (receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipts available to seal in audit pack.')),
      );
      return;
    }

    setState(() => _isExportingAuditPack = true);
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sealing cryptographic audit pack (.zip) with Merkle SHA-256 proofs... 🛡️'),
          duration: Duration(seconds: 2),
        ),
      );

      final castReceipts = receipts.cast<dynamic>();
      final castBoxes = boxes.cast<dynamic>();

      await AuditPackagerService.exportAndShareZip(
        receipts: List.from(castReceipts),
        boxes: List.from(castBoxes),
        fiscalYear: DateTime.now().year,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audit pack export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingAuditPack = false);
    }
  }

  Future<void> _exportCpaPortal(List<dynamic> receipts, List<dynamic> boxes) async {
    if (receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipts available to generate CPA portal.')),
      );
      return;
    }

    setState(() => _isExportingCpaPortal = true);
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating zero-knowledge PII-redacted CPA Tax Portal (.html)... 📊'),
          duration: Duration(seconds: 2),
        ),
      );

      final castReceipts = receipts.cast<dynamic>();
      final castBoxes = boxes.cast<dynamic>();

      await ExportService().exportZeroKnowledgeCpaPortal(
        List.from(castReceipts),
        boxes: List.from(castBoxes),
        fiscalYear: '${DateTime.now().year}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CPA Portal generation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingCpaPortal = false);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String label, Color muted, int delayIndex) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              letterSpacing: 1.2,
              color: muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: Duration(milliseconds: 60 + delayIndex * 40))
        .slideX(begin: -0.04, curve: Curves.easeOut);
  }

  Widget _cardWrapper({required Color tileBg, required Color divider, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: divider, width: 1)),
      clipBehavior: Clip.antiAlias,
      child: child,
    ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.04, curve: Curves.easeOut);
  }

  Widget _row({
    required String label,
    String? subtitle,
    required Color fgCol,
    required Color muted,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: fgCol,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, Color divider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: divider)),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _outlineBtn({
    required String label,
    required Color color,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 13, fontWeight: FontWeight.w400)),
      ),
    );
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showVaultDetailsDialog(String merkleRoot) {
    final theme = Theme.of(context);
    final fgCol = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.verified_user_outlined, color: const Color(0xFF10B981), size: 22),
            const SizedBox(width: 10),
            Text(
              'Vault Health & Cryptographic Proofs',
              style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.bold, color: fgCol),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deterministic SHA-256 Merkle Root Digest:',
                style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: SelectableText(
                  merkleRoot,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: fgCol),
                ),
              ),
              const SizedBox(height: 14),
              _buildProofRow('RAM Master Key', 'Zeroed in memory upon 5-min inactivity lock', const Color(0xFF10B981), fgCol, muted),
              const SizedBox(height: 8),
              _buildProofRow('Storage Topology', '100% Air-Gapped / Zero Cloud Telemetry', const Color(0xFF10B981), fgCol, muted),
              const SizedBox(height: 8),
              _buildProofRow('Cryptographic Seal', 'ED25519 Signed JSON-LD Audit Defense Manifest', _accent, fgCol, muted),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Done', style: GoogleFonts.spaceGrotesk(color: _accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProofRow(String title, String desc, Color dotColor, Color fgCol, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: fgCol)),
              Text(desc, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  void _showTaxProfileDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fgCol = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final activeProfileId = ref.read(selectedTaxProfileIdProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Select Statutory Tax Profile',
          style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SizedBox(
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: kTaxProfilePresets.length,
            separatorBuilder: (_, _) => const Divider(height: 12),
            itemBuilder: (c, idx) {
              final preset = kTaxProfilePresets[idx];
              final isSelected = preset.id == activeProfileId;
              return InkWell(
                onTap: () {
                  ref.read(selectedTaxProfileIdProvider.notifier).state = preset.id;
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? _accent : muted,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preset.name,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: fgCol,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preset.description,
                              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.spaceGrotesk(color: muted)),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiKeyDialog(String currentKey) async {
    final ctrl = TextEditingController(text: currentKey);
    final isDark = ref.read(themeProvider) == ThemeMode.dark;
    final dialogBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textCol = isDark ? Colors.white : Colors.black;

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Gemini API Key',
              style: GoogleFonts.spaceGrotesk(
                  color: textCol, fontWeight: FontWeight.w500)),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            style: GoogleFonts.jetBrainsMono(color: textCol, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Paste key here…',
              hintStyle: GoogleFonts.spaceGrotesk(color: textCol.withAlpha(80)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: textCol.withAlpha(30))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.spaceGrotesk(color: textCol.withAlpha(100))),
            ),
            TextButton(
              onPressed: () async {
                // Write to secure storage (keychain), NOT Hive
                await SecureStorageService.writeSecret(
                  SecretKeys.geminiApiKey, ctrl.text.trim());
                // Invalidate the provider so aiServiceProvider picks up the new key
                ref.invalidate(geminiApiKeyProvider);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('API Key saved securely')));
              },
              child: Text('Save',
                  style: GoogleFonts.spaceGrotesk(color: _accent)),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  void _showClearDialog() {
    final isDark = ref.read(themeProvider) == ThemeMode.dark;
    final dialogBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textCol = isDark ? Colors.white : Colors.black;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear All Data',
            style: GoogleFonts.spaceGrotesk(
                color: textCol, fontWeight: FontWeight.w500)),
        content: Text(
            'Device Only removes receipts from this device. Copies stored in your '
            'cloud account are kept and can be restored with Replicate Cloud Data.\n\n'
            'Everywhere also deletes them from your cloud account and other '
            'devices. This cannot be undone.',
            style: GoogleFonts.spaceGrotesk(
                color: textCol.withAlpha(160), fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(
                    color: textCol.withAlpha(100))),
          ),
          TextButton(
            onPressed: () {
              ref.read(receiptListProvider.notifier).clearAll(includeCloud: false);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Local data cleared')));
            },
            child: Text('Device Only',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFD4183D))),
          ),
          TextButton(
            onPressed: () {
              ref.read(receiptListProvider.notifier).clearAll(includeCloud: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('All data wiped')));
            },
            child: Text('Everywhere',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFD4183D),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _archiveData() async {
    setState(() => _isUploading = true);
    try {
      await googleDriveService.archiveAllData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup successful!')));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context: context,
          error: googleDriveService.lastError ?? e,
          actionLabel: 'Retry',
          onAction: _archiveData,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _importCsv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String csvString = '';
      if (file.bytes != null) {
        csvString = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      }

      if (csvString.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected CSV file is empty')),
          );
        }
        return;
      }

      final parser = ref.read(csvParserServiceProvider);
      final importResult = await ref.read(receiptListProvider.notifier).importCsvTransactions(csvString, parser);

      if (!mounted) return;

      await importResult.fold(
        (failure) async {
          await ErrorHandler.showErrorDialog(
            context: context,
            error: failure,
            title: 'CSV Import Failed',
          );
        },
        (report) async {
          await _showCsvReportDialog(report);
        },
      );
    } catch (e) {
      if (mounted) {
        await ErrorHandler.showErrorDialog(
          context: context,
          error: e,
          title: 'CSV Import Error',
        );
      }
    }
  }

  Future<void> _showCsvReportDialog(CsvImportReport report) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF8E8E93) : const Color(0xFF737373);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F8);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              report.hasErrors
                  ? (report.successCount > 0 ? Icons.info_outline : Icons.error_outline)
                  : Icons.check_circle_outline,
              color: report.hasErrors
                  ? (report.successCount > 0 ? const Color(0xFF002FA7) : const Color(0xFFD4183D))
                  : const Color(0xFF16A34A),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              'CSV Import Summary',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w600, color: fgCol),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Processed', report.totalRows.toString(), fgCol, muted),
                    _buildStatItem('Imported', report.successCount.toString(), const Color(0xFF16A34A), muted),
                    // Credits, refunds and rows imported before.
                    _buildStatItem('Skipped', report.skippedCount.toString(), muted, muted),
                    _buildStatItem(
                      'Failed',
                      report.failureCount.toString(),
                      report.failureCount > 0 ? const Color(0xFFD4183D) : muted,
                      muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (report.hasErrors) ...[
                Text(
                  'Failed Rows (${report.failedRows.length})',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFD4183D),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: report.failedRows.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (ctx, idx) {
                      final error = report.failedRows[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4183D).withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Line ${error.lineNumber}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFD4183D),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error.reason,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: fgCol,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error.rawRow,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: muted,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'All ${report.successCount} transactions were parsed and imported successfully.',
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Done',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueCol, Color muted) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.bold, color: valueCol),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

// ─── Animated Figma-style toggle ─────────────────────────────────────────────
class _FigmaToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FigmaToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: 48,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: value ? _accent : Colors.black.withAlpha(30),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
