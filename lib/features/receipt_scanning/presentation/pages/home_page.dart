import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/receipt_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../settings/presentation/providers/llm_provider.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../widgets/interactive_hover.dart';
import '../widgets/dashboard/customizable_metrics_grid.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isEditMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final receiptListAsync = ref.watch(filteredReceiptsByActiveBoxProvider);
    final fgCol = colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.spaceGrotesk(color: fgCol),
                decoration: InputDecoration(
                  hintText: 'Search merchant...',
                  hintStyle: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ).animate().fadeIn().slideX(begin: 0.05)
            : Text(_isEditMode ? 'Edit Layout' : 'tAIdy', style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.w500, fontSize: 24)),
        leading: _isSearching
            ? IconButton(icon: Icon(Icons.close, color: fgCol), onPressed: () => setState(() { _isSearching = false; _searchController.clear(); }))
            : null,
        actions: _buildAppBarActions(fgCol, colorScheme.primary),
      ),
      body: receiptListAsync.when(
        data: (receipts) => CustomizableMetricsGrid(
          receipts: receipts,
          isDark: isDark,
          isEditMode: _isEditMode,
          searchQuery: _searchController.text,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: fgCol))),
      ),
      bottomNavigationBar: _isEditMode ? null : _buildBottomNav(colorScheme),
    );
  }

  List<Widget> _buildAppBarActions(Color fgCol, Color accent) {
    if (_isEditMode) {
      return [
        TextButton.icon(
          onPressed: () {
            ref.read(dashboardProvider.notifier).reset();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layout reset!')));
          },
          icon: Icon(Icons.restore, color: fgCol),
          label: Text('Reset', style: GoogleFonts.spaceGrotesk(color: fgCol)),
        ),
        IconButton(icon: Icon(Icons.check_circle, color: accent), onPressed: () => setState(() => _isEditMode = false)),
      ];
    }
    if (!_isSearching) {
      return [
        IconButton(icon: Icon(Icons.search, color: fgCol), onPressed: () => setState(() => _isSearching = true)),
        IconButton(icon: Icon(Icons.shield_outlined, color: fgCol), onPressed: () => context.push('/vault')),
        IconButton(icon: Icon(Icons.dashboard_customize, color: fgCol), onPressed: () => setState(() => _isEditMode = true)),
        IconButton(
          icon: Icon(Icons.visibility_off_outlined, color: fgCol),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy mode toggled.'))),
        ),
        IconButton(icon: Icon(Icons.download, color: fgCol), onPressed: _exportCsv),
        IconButton(icon: Icon(Icons.settings, color: fgCol), onPressed: () => _showSettingsPanel(context)),
      ].animate(interval: 30.ms).fadeIn(duration: 200.ms).slideY(begin: 0.1, duration: 200.ms);
    }
    return [IconButton(icon: Icon(Icons.check, color: fgCol), onPressed: () => FocusManager.instance.primaryFocus?.unfocus())];
  }

  Widget _buildBottomNav(ColorScheme colorScheme) {
    final isLlmActive = ref.watch(isLlmLoadedProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isLlmActive ? Colors.greenAccent : Colors.grey))
                      .animate(target: isLlmActive ? 1 : 0, onPlay: (c) => isLlmActive ? c.repeat(reverse: true) : null)
                      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 1.seconds),
                  const SizedBox(width: 8),
                  Text(isLlmActive ? 'AI Core Active' : 'AI Offline', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            InteractiveHover(
              onTap: () => context.push('/scan'),
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.primary, boxShadow: [BoxShadow(color: colorScheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
                child: Center(child: Icon(Icons.camera_alt, color: colorScheme.onPrimary, size: 32)),
              ).animate().scale(delay: 500.ms, curve: Curves.elasticOut),
            ),
            const SizedBox(width: 120),
          ],
        ),
      ),
    );
  }

  void _showSettingsPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, anim, secAnim) => const SettingsPanelWidget(),
      transitionBuilder: (ctx, animation, secAnim, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return Stack(
          children: [
            AnimatedBuilder(
              animation: curved,
              builder: (ctx, ch) => BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12 * curved.value, sigmaY: 12 * curved.value),
                child: GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: Container(color: Colors.black.withAlpha((120 * curved.value).round()))),
              ),
            ),
            SlideTransition(position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved), child: child),
          ],
        );
      },
    );
  }

  void _exportCsv() {
    ref.read(receiptListProvider).whenData((receipts) {
      if (receipts.isNotEmpty) {
        ref.read(exportServiceProvider).exportReceiptsToCsv(receipts);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating CSV Report...')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No receipts to export')));
      }
    });
  }
}
