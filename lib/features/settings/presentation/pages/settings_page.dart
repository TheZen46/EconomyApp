import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/theme_notifier.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../receipt_scanning/data/datasources/csv_parser_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../receipt_scanning/data/models/sync_item_model.dart';
import '../../../../core/services/google_drive_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/routes/app_router.dart';
import '../../../sync/presentation/providers/sync_provider.dart';

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
  bool _isEditingBudget = false;
  late TextEditingController _budgetCtrl;
  final _budgetFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final box = ref.read(settingsBoxProvider);
    _isDevMode = box.get('is_dev_mode', defaultValue: false) as bool;
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
        ref.read(settingsBoxProvider).put('is_dev_mode', true);
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
                              'SETTINGS',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                letterSpacing: 1.4,
                                color: muted,
                                fontWeight: FontWeight.w400,
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
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 80),
                    children: [

                      // ── General ─────────────────────────────────────────
                      _sectionHeader(Icons.settings_outlined, 'General', muted, 0),
                      const SizedBox(height: 12),

                      // Monthly Budget
                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('Monthly Budget',
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w300,
                                        color: fgCol)),
                              ),
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
                      ),
                      const SizedBox(height: 8),

                      // Dark mode toggle
                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Icon(Icons.nightlight_outlined, color: _accent, size: 16),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Dark mode',
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w300,
                                        color: fgCol)),
                              ),
                              _FigmaToggle(
                                value: isDark,
                                onChanged: (_) =>
                                    ref.read(themeProvider.notifier).toggle(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── AI Engine ────────────────────────────────────────
                      _sectionHeader(Icons.psychology_outlined, 'AI Engine', muted, 1),
                      const SizedBox(height: 12),

                      Consumer(builder: (context, ref, _) {
                        final box = ref.watch(settingsBoxProvider);
                        final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
                        // Read API key from secure storage asynchronously
                        final apiKeyAsync = ref.watch(geminiApiKeyProvider);
                        final apiKey = apiKeyAsync.valueOrNull ?? '';
                        return _cardWrapper(
                          tileBg: tileBg,
                          divider: divider,
                          child: Column(children: [
                            _row(label: 'Local AI Brain Models', fgCol: fgCol, muted: muted,
                                trailing: _chip('Manage', muted, divider),
                                onTap: () { Navigator.of(context).pop(); context.push('/model_manager'); }),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            _row(label: 'Enable Gemini AI', fgCol: fgCol, muted: muted,
                                trailing: _FigmaToggle(
                                  value: isEnabled,
                                  onChanged: (val) {
                                    box.put('enable_gemini_ai', val);
                                    setState(() {});
                                  },
                                )),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            _row(
                                label: 'Set API Key…',
                                fgCol: isEnabled ? fgCol : muted,
                                muted: muted,
                                onTap: isEnabled ? () => _showApiKeyDialog(apiKey) : null,
                                trailing: isEnabled
                                    ? Icon(Icons.edit_outlined, size: 16, color: muted)
                                    : null),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            Opacity(
                              opacity: 0.4,
                              child: _row(label: 'Distributed Inference', fgCol: fgCol, muted: muted,
                                  trailing: _FigmaToggle(value: false, onChanged: (_) {})),
                            ),
                          ]),
                        );
                      }),

                      const SizedBox(height: 28),

                      // ── Customization ────────────────────────────────────
                      _sectionHeader(Icons.palette_outlined, 'Customization', muted, 2),
                      const SizedBox(height: 12),

                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Column(children: [
                          _row(label: 'Manage Categories', fgCol: fgCol, muted: muted,
                              trailing: Icon(Icons.chevron_right, size: 18, color: muted),
                              onTap: () { Navigator.of(context).pop(); context.push('/taxonomy'); }),
                          Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                          _row(label: 'Integrations & Webhooks', fgCol: fgCol, muted: muted,
                              trailing: Icon(Icons.chevron_right, size: 18, color: muted),
                              onTap: () { Navigator.of(context).pop(); context.push('/integrations'); }),
                        ]),
                      ),

                      const SizedBox(height: 28),

                      // ── Data & Privacy ───────────────────────────────────
                      _sectionHeader(Icons.storage_outlined, 'Data & Privacy', muted, 3),
                      const SizedBox(height: 12),

                      _cardWrapper(tileBg: tileBg, divider: divider, child:
                        Column(
                          children: [
                            Consumer(builder: (context, ref, _) {
                              final isBiometricEnabled = ref.watch(biometricEnabledProvider);
                              return _row(
                                label: 'Biometric Lock (FaceID / Fingerprint)',
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
                                    }
                                    await ref.read(biometricEnabledProvider.notifier).setEnabled(val);
                                  },
                                ),
                              );
                            }),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            storageAsync.when(
                              data: (bytes) => _row(
                                  label: 'Dataset Contribution',
                                  fgCol: fgCol, muted: muted,
                                  trailing: Text('${(bytes / 1024).toStringAsFixed(1)} KB',
                                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: muted)),
                                  onTap: () => ref.refresh(storageUsageProvider)),
                              loading: () => _row(
                                  label: 'Dataset Contribution',
                                  fgCol: fgCol, muted: muted,
                                  trailing: SizedBox(width: 14, height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))),
                              error: (err, stack) => _row(
                                  label: 'Dataset Contribution',
                                  fgCol: fgCol, muted: muted,
                                  trailing: Text('Error', style: GoogleFonts.spaceGrotesk(
                                      fontSize: 12, color: const Color(0xFFD4183D)))),
                            ),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            _row(
                              label: 'Import Bank CSV',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: Icon(Icons.file_upload_outlined, size: 18, color: muted),
                              onTap: _importCsv,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Sync Center ──────────────────────────────────────
                      Consumer(builder: (context, ref, _) {
                        final syncItemsAsync = ref.watch(syncQueueStreamProvider);
                        final syncItems = syncItemsAsync.valueOrNull ?? [];
                        final failedItems = syncItems.where((i) => i.status == SyncStatus.permanentlyFailed).toList();
                        final pendingItems = syncItems.where((i) => i.status != SyncStatus.permanentlyFailed).toList();

                        return _cardWrapper(
                          tileBg: tileBg,
                          divider: divider,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row(
                                label: 'Sync Center',
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
                          ),
                        );
                      }),

                      const SizedBox(height: 12),

                      // Clear All Data
                      _outlineBtn(
                          label: 'Clear All Data',
                          color: const Color(0xFFD4183D),
                          borderColor: const Color(0xFFD4183D).withAlpha(60),
                          onTap: () => _showClearDialog()),

                      const SizedBox(height: 8),

                      // Log Out
                      _outlineBtn(
                          label: 'Log Out',
                          color: muted,
                          borderColor: divider,
                          onTap: () async {
                            Navigator.of(context).pop();
                            // Sign out via Supabase — the auth stream triggers
                            // RouterNotifier which redirects to '/' automatically.
                            await ref.read(authProvider.notifier).signOut();
                          }),

                      // ── Dev Mode ─────────────────────────────────────────
                      if (_isDevMode) ...[
                        const SizedBox(height: 28),
                        _sectionHeader(Icons.developer_mode_outlined, 'Admin Tools', muted, 4),
                        const SizedBox(height: 12),
                        Consumer(builder: (context, ref, _) {
                          final box = ref.watch(settingsBoxProvider);
                          final useDrive = box.get('use_google_drive_storage', defaultValue: false) as bool;
                          return _cardWrapper(tileBg: tileBg, divider: divider, child:
                            Column(children: [
                              _row(label: 'Storage Provider: Google Drive', fgCol: fgCol, muted: muted,
                                  trailing: _FigmaToggle(value: useDrive, onChanged: (val) {
                                    box.put('use_google_drive_storage', val);
                                    setState(() {});
                                  })),
                              Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                              _row(
                                  label: _isUploading ? 'Uploading…' : 'Archive All Data Now',
                                  fgCol: fgCol, muted: muted,
                                  trailing: _isUploading
                                      ? SizedBox(width: 14, height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: muted))
                                      : Icon(Icons.backup_outlined, size: 16, color: muted),
                                  onTap: _isUploading ? null : _archiveData),
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
                            'tAIdy v0.3.0 (Beta)${_isDevMode ? " [DEV]" : ""}',
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

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String label, Color muted, int delayIndex) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 16),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, letterSpacing: 1.2, color: muted,
                fontWeight: FontWeight.w400)),
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
    required Color fgCol,
    required Color muted,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w300, color: fgCol)),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  Widget _chip(String label, Color muted, Color divider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: divider)),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted)),
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

  void _showApiKeyDialog(String currentKey) {
    final ctrl = TextEditingController(text: currentKey);
    final isDark = ref.read(themeProvider) == ThemeMode.dark;
    final dialogBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textCol = isDark ? Colors.white : Colors.black;

    showDialog(
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
        content: Text('This cannot be undone. Choose what to delete.',
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
                    _buildStatItem(
                      'Skipped',
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
