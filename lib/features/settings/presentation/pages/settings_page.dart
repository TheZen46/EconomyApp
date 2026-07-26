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

    final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;
    final fgCol = isDark ? Colors.white : Colors.black;
    final muted = fgCol.withAlpha(102);
    final divider = isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10);
    final tileBg = isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F9);

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
                        final apiKey = box.get('gemini_api_key', defaultValue: '') as String;
                        final isEnabled = box.get('enable_gemini_ai', defaultValue: false) as bool;
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
                                    if (val && box.get('gemini_api_key') == null) box.put('gemini_api_key', '');
                                    setState(() {});
                                  },
                                )),
                            Divider(color: divider, height: 1, indent: 20, endIndent: 20),
                            _row(
                                label: 'Set API Key…',
                                fgCol: isEnabled ? fgCol : muted,
                                muted: muted,
                                onTap: isEnabled ? () => _showApiKeyDialog(box, apiKey) : null,
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
                          error: (_, __) => _row(
                              label: 'Dataset Contribution',
                              fgCol: fgCol, muted: muted,
                              trailing: Text('Error', style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, color: const Color(0xFFD4183D)))),
                        ),
                      ),

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
                          onTap: () {
                            ref.read(settingsBoxProvider).put('isLoggedIn', false);
                            Navigator.of(context).pop();
                            context.go('/');
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

  void _showApiKeyDialog(dynamic box, String currentKey) {
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
            onPressed: () {
              box.put('gemini_api_key', ctrl.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('API Key saved')));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${googleDriveService.lastError ?? e}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
