// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/theme_notifier.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../../core/services/google_drive_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const _accent = Color(0xFF002FA7);

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // Dev-mode easter egg
  int _devModeClicks = 0;
  bool _isDevMode = false;
  bool _isUploading = false;

  // Inline budget editing
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

    final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withAlpha(102); // ~40%
    final divider = isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10);
    final tileBg = isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F9);

    final storageAsync = ref.watch(storageUsageProvider);
    final currentBudget = ref.watch(monthlyBudgetProvider);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(color: divider, width: 1),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: divider, width: 1),
                      ),
                      child: Icon(Icons.arrow_back, color: fgCol, size: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
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
                ],
              ),
            ).animate().fadeIn(duration: 250.ms),

            // ── Content ─────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
                children: [

                  // ── SECTION: General ─────────────────────────────────────
                  _sectionHeader(Icons.settings_outlined, 'General', fgCol, muted),
                  const SizedBox(height: 12),

                  // Monthly Budget row
                  _rowWrapper(
                    isDark: isDark,
                    tileBg: tileBg,
                    divider: divider,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Monthly Budget',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                color: fgCol,
                              ),
                            ),
                          ),
                          _isEditingBudget
                              ? SizedBox(
                                  width: 120,
                                  child: Row(
                                    children: [
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
                                              borderSide:
                                                  const BorderSide(color: _accent),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide:
                                                  const BorderSide(color: _accent),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: divider),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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

                  // Dark Mode toggle row
                  _rowWrapper(
                    isDark: isDark,
                    tileBg: tileBg,
                    divider: divider,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.nightlight_outlined, color: _accent, size: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Dark mode',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                color: fgCol,
                              ),
                            ),
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

                  const SizedBox(height: 32),

                  // ── SECTION: AI Engine ───────────────────────────────────
                  _sectionHeader(Icons.psychology_outlined, 'AI Engine', fgCol, muted),
                  const SizedBox(height: 12),

                  Consumer(builder: (context, ref, _) {
                    final box = ref.watch(settingsBoxProvider);
                    final apiKey =
                        box.get('gemini_api_key', defaultValue: '') as String;
                    final isEnabled =
                        box.get('enable_gemini_ai', defaultValue: false) as bool;

                    return _rowWrapper(
                      isDark: isDark,
                      tileBg: tileBg,
                      divider: divider,
                      child: Column(
                        children: [
                          // Local AI Brain Models
                          _settingsRow(
                            label: 'Local AI Brain Models',
                            fgCol: fgCol,
                            muted: muted,
                            trailing: _chipLabel('Manage', muted, divider),
                            onTap: () => context.push('/model_manager'),
                          ),
                          Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                          // Enable Gemini AI toggle
                          _settingsRow(
                            label: 'Enable Gemini AI',
                            fgCol: fgCol,
                            muted: muted,
                            trailing: _FigmaToggle(
                              value: isEnabled,
                              onChanged: (val) {
                                box.put('enable_gemini_ai', val);
                                if (val && box.get('gemini_api_key') == null) {
                                  box.put('gemini_api_key', '');
                                }
                                setState(() {});
                              },
                            ),
                          ),
                          Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                          // API Key
                          _settingsRow(
                            label: 'Set API Key…',
                            fgCol: isEnabled ? fgCol : muted,
                            muted: muted,
                            onTap: isEnabled
                                ? () => _showApiKeyDialog(context, box, apiKey)
                                : null,
                            trailing: isEnabled
                                ? Icon(Icons.edit_outlined,
                                    size: 16, color: muted)
                                : null,
                          ),
                          Divider(color: divider, height: 1, indent: 20, endIndent: 20),

                          // Distributed Inference (disabled)
                          Opacity(
                            opacity: 0.4,
                            child: _settingsRow(
                              label: 'Distributed Inference',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _FigmaToggle(
                                value: false,
                                onChanged: (_) {},
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 32),

                  // ── SECTION: Customization ───────────────────────────────
                  _sectionHeader(Icons.palette_outlined, 'Customization', fgCol, muted),
                  const SizedBox(height: 12),

                  _rowWrapper(
                    isDark: isDark,
                    tileBg: tileBg,
                    divider: divider,
                    child: Column(
                      children: [
                        _settingsRow(
                          label: 'Manage Categories',
                          fgCol: fgCol,
                          muted: muted,
                          onTap: () => context.push('/taxonomy'),
                          trailing:
                              Icon(Icons.chevron_right, size: 18, color: muted),
                        ),
                        Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                        _settingsRow(
                          label: 'Integrations & Webhooks',
                          fgCol: fgCol,
                          muted: muted,
                          onTap: () => context.push('/integrations'),
                          trailing:
                              Icon(Icons.chevron_right, size: 18, color: muted),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── SECTION: Data & Privacy ──────────────────────────────
                  _sectionHeader(Icons.storage_outlined, 'Data & Privacy', fgCol, muted),
                  const SizedBox(height: 12),

                  _rowWrapper(
                    isDark: isDark,
                    tileBg: tileBg,
                    divider: divider,
                    child: Column(
                      children: [
                        // Dataset contribution
                        storageAsync.when(
                          data: (bytes) => _settingsRow(
                            label: 'Dataset Contribution',
                            fgCol: fgCol,
                            muted: muted,
                            trailing: Text(
                              '${(bytes / 1024).toStringAsFixed(1)} KB',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12, color: muted),
                            ),
                            onTap: () => ref.refresh(storageUsageProvider),
                          ),
                          loading: () => _settingsRow(
                            label: 'Dataset Contribution',
                            fgCol: fgCol,
                            muted: muted,
                            trailing: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: muted),
                            ),
                          ),
                          error: (_, __) => _settingsRow(
                            label: 'Dataset Contribution',
                            fgCol: fgCol,
                            muted: muted,
                            trailing: Text('Error',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    color: const Color(0xFFD4183D))),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Clear All Data button
                  _destructiveButton(
                    label: 'Clear All Data',
                    isDark: isDark,
                    onTap: () => _showClearDataDialog(context),
                  ),

                  const SizedBox(height: 8),

                  // Log Out button
                  _outlineButton(
                    label: 'Log Out',
                    fgCol: fgCol,
                    muted: muted,
                    divider: divider,
                    onTap: () {
                      ref.read(settingsBoxProvider).put('isLoggedIn', false);
                      context.go('/');
                    },
                  ),

                  // ── Dev Mode Section ─────────────────────────────────────
                  if (_isDevMode) ...[
                    const SizedBox(height: 32),
                    _sectionHeader(Icons.developer_mode_outlined, 'Admin Tools', fgCol, muted),
                    const SizedBox(height: 12),

                    Consumer(builder: (context, ref, _) {
                      final box = ref.watch(settingsBoxProvider);
                      final useDrive = box.get('use_google_drive_storage',
                          defaultValue: false) as bool;
                      return _rowWrapper(
                        isDark: isDark,
                        tileBg: tileBg,
                        divider: divider,
                        child: Column(
                          children: [
                            _settingsRow(
                              label: 'Storage Provider: Google Drive',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _FigmaToggle(
                                value: useDrive,
                                onChanged: (val) {
                                  box.put('use_google_drive_storage', val);
                                  setState(() {});
                                },
                              ),
                            ),
                            Divider(
                                color: divider, height: 1, indent: 20, endIndent: 20),
                            _settingsRow(
                              label: _isUploading
                                  ? 'Uploading…'
                                  : 'Archive All Data Now',
                              fgCol: fgCol,
                              muted: muted,
                              trailing: _isUploading
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5, color: muted))
                                  : Icon(Icons.backup_outlined,
                                      size: 16, color: muted),
                              onTap: _isUploading ? null : _archiveData,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // ── Version footer ───────────────────────────────────────
                  const SizedBox(height: 48),
                  GestureDetector(
                    onTap: _onVersionTap,
                    child: Center(
                      child: Text(
                        'tAIdy v0.3.0 (Beta)${_isDevMode ? " [DEV]" : ""}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          color: muted.withAlpha(128),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String label, Color fgCol, Color muted) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 16),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            letterSpacing: 1.2,
            color: muted,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 50.ms).slideX(begin: -0.05, curve: Curves.easeOut);
  }

  Widget _rowWrapper({
    required bool isDark,
    required Color tileBg,
    required Color divider,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.04, curve: Curves.easeOut);
  }

  Widget _settingsRow({
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                  color: fgCol,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _chipLabel(String text, Color muted, Color divider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: divider),
      ),
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(fontSize: 11, color: muted),
      ),
    );
  }

  Widget _destructiveButton(
      {required String label, required bool isDark, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFD4183D),
          side: const BorderSide(color: Color(0xFFD4183D), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w400),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required Color fgCol,
    required Color muted,
    required Color divider,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: muted,
          side: BorderSide(color: divider, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w400),
        ),
      ),
    );
  }

  // ── Dialog helpers ─────────────────────────────────────────────────────────

  void _showApiKeyDialog(BuildContext context, dynamic box, String currentKey) {
    final ctrl = TextEditingController(text: currentKey);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark =
            ref.read(themeProvider) == ThemeMode.dark;
        final dialogBg =
            isDark ? const Color(0xFF1A1A1A) : Colors.white;
        final textCol = isDark ? Colors.white : Colors.black;
        return AlertDialog(
          backgroundColor: dialogBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Gemini API Key',
              style: GoogleFonts.spaceGrotesk(
                  color: textCol, fontWeight: FontWeight.w500)),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            style: GoogleFonts.jetBrainsMono(color: textCol, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Paste key here…',
              hintStyle: GoogleFonts.spaceGrotesk(
                  color: textCol.withAlpha(80)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: textCol.withAlpha(30))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.spaceGrotesk(
                      color: textCol.withAlpha(100))),
            ),
            TextButton(
              onPressed: () {
                box.put('gemini_api_key', ctrl.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API Key saved')));
              },
              child: Text('Save',
                  style: GoogleFonts.spaceGrotesk(color: _accent)),
            ),
          ],
        );
      },
    );
  }

  void _showClearDataDialog(BuildContext context) {
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
          'This cannot be undone. Choose what to delete.',
          style: GoogleFonts.spaceGrotesk(
              color: textCol.withAlpha(160), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(
                    color: textCol.withAlpha(100))),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(receiptListProvider.notifier)
                  .clearAll(includeCloud: false);
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
              ref
                  .read(receiptListProvider.notifier)
                  .clearAll(includeCloud: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data wiped')));
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup successful!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${googleDriveService.lastError ?? e}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}

// ─── Figma Toggle ─────────────────────────────────────────────────────────────
class _FigmaToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FigmaToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 48,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: value ? _accent : Colors.black.withAlpha(30),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
