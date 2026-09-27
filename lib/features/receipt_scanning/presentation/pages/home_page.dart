import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../providers/receipt_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../settings/presentation/providers/llm_provider.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/interactive_hover.dart';
import '../widgets/dashboard/customizable_metrics_grid.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../boxes/presentation/widgets/box_creator_sheet.dart';
import '../../data/models/sync_item_model.dart';
import '../../../../core/sync/sync_providers.dart';

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

  void _exportCsv() {
    final receipts = ref.read(filteredReceiptsByActiveBoxProvider).valueOrNull ?? [];
    if (receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipts to export.')),
      );
      return;
    }
    final csvService = ref.read(exportServiceProvider);
    csvService.exportReceiptsToCsv(receipts);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receipts exported to CSV successfully! 📊')),
    );
  }

  void _showBoxSwitcher(BuildContext context) {
    final boxes = ref.read(boxesProvider);
    final activeBoxId = ref.read(activeBoxIdProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inventory_2_outlined, color: AppColors.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Select Active Box',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: fgCol,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: muted, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Filter and isolate your financial dashboard, burn rate, and runway calculations per context.',
                style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: boxes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final box = boxes[index];
                    final isSelected = box.id == activeBoxId;
                    final boxColor = Color(box.color);

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          ref.read(activeBoxIdProvider.notifier).state = box.id;
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? boxColor.withOpacity(0.12)
                                : colorScheme.surfaceContainer.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? boxColor : Colors.white.withOpacity(0.05),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: boxColor,
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: boxColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      box.name,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: fgCol,
                                      ),
                                    ),
                                    if (box.budget > 0)
                                      Text(
                                        'Budget: \$${box.budget.toStringAsFixed(0)} | Spent: \$${box.spent.toStringAsFixed(0)}',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
                                      ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: boxColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fgCol,
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const BoxCreatorSheet(),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Create New Box', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showSyncTelemetrySheet(BuildContext context) {
    final syncQueue = ref.read(syncQueueStreamProvider).valueOrNull ?? [];
    final pendingCount = syncQueue.where((item) => item.status == SyncStatus.pending || item.status == SyncStatus.inProgress).length;
    final failedCount = syncQueue.where((item) => item.status == SyncStatus.permanentlyFailed).length;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Cloud Telemetry & Sync HUD',
                        style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: fgCol),
                      ),
                    ],
                  ),
                  IconButton(icon: Icon(Icons.close, color: muted, size: 20), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outline),
                ),
                child: Column(
                  children: [
                    _syncTelemetryRow('Cloud Connection', 'Supabase Realtime Active', const Color(0xFF10B981), fgCol, muted),
                    const Divider(height: 20),
                    _syncTelemetryRow('Sync Queue', '$pendingCount items pending', pendingCount > 0 ? Colors.amber : const Color(0xFF10B981), fgCol, muted),
                    const Divider(height: 20),
                    _syncTelemetryRow('Failed Retries', '$failedCount items failed', failedCount > 0 ? AppTheme.error : muted, fgCol, muted),
                    const Divider(height: 20),
                    _syncTelemetryRow('Last Delta Sync', DateFormat('HH:mm:ss — dd MMM yyyy').format(DateTime.now()), muted, fgCol, muted),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Forcing Cloud Delta Sync... 🔄')),
                    );
                    try {
                      await ref.read(syncManagerProvider)?.syncAll();
                      await ref.read(syncServiceProvider).syncPendingItems();
                      await ref.read(receiptListProvider.notifier).loadReceipts();
                      ref.read(boxesProvider.notifier).reload();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Cloud sync completed successfully! 🟢')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Sync notice: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text('Force Sync Now', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncTelemetryRow(String label, String value, Color statusColor, Color fgCol, Color muted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: muted)),
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
            const SizedBox(width: 8),
            Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: fgCol)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final receiptListAsync = ref.watch(filteredReceiptsByActiveBoxProvider);
    final fgCol = colorScheme.onSurface;

    // Active box details
    final boxes = ref.watch(boxesProvider);
    final activeBoxId = ref.watch(activeBoxIdProvider);
    final activeBox = boxes.firstWhere(
      (b) => b.id == activeBoxId,
      orElse: () => BoxModel(id: 'main', name: 'Main Life', budget: 0, spent: 0, currency: 'USD', color: 0xFF002FA7),
    );

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
                  hintText: 'Search merchant or item...',
                  hintStyle: GoogleFonts.spaceGrotesk(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ).animate().fadeIn().slideX(begin: 0.05)
            : _isEditMode
                ? Text('Edit Layout', style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.w500, fontSize: 24))
                : Row(
                    children: [
                      Text('tAIdy', style: GoogleFonts.spaceGrotesk(color: fgCol, fontWeight: FontWeight.w500, fontSize: 24)),
                      const SizedBox(width: 12),
                      _buildBoxContextSelector(activeBox, fgCol, colorScheme),
                    ],
                  ),
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.close, color: fgCol),
                onPressed: () => setState(() {
                  _isSearching = false;
                  _searchController.clear();
                }),
              )
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

  Widget _buildBoxContextSelector(BoxModel activeBox, Color fgCol, ColorScheme colorScheme) {
    final boxColor = Color(activeBox.color);

    return GestureDetector(
      onTap: () => _showBoxSwitcher(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: boxColor.withOpacity(0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: boxColor.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: boxColor,
                boxShadow: [
                  BoxShadow(color: boxColor.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                activeBox.name,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fgCol,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
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
      // Cloud sync state watcher
      final syncQueue = ref.watch(syncQueueStreamProvider).valueOrNull ?? [];
      final isSyncing = syncQueue.any((i) => i.status == SyncStatus.inProgress);
      final hasPending = syncQueue.any((i) => i.status == SyncStatus.pending);
      final hasFailed = syncQueue.any((i) => i.status == SyncStatus.permanentlyFailed);

      Color syncDotColor = const Color(0xFF10B981); // Emerald
      if (isSyncing) {
        syncDotColor = const Color(0xFF0891B2); // Pulsing cyan
      } else if (hasFailed) {
        syncDotColor = AppColors.destructive;
      } else if (hasPending) {
        syncDotColor = const Color(0xFFF59E0B); // Amber
      }

      return [
        // Cloud Sync Telemetry Button
        GestureDetector(
          onTap: () => _showSyncTelemetrySheet(context),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: syncDotColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: syncDotColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: syncDotColor,
                    boxShadow: [
                      BoxShadow(color: syncDotColor.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
                    ],
                  ),
                ).animate(target: isSyncing ? 1 : 0, onPlay: (c) => isSyncing ? c.repeat(reverse: true) : null)
                 .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.3, 1.3), duration: 800.ms),
                const SizedBox(width: 5),
                Icon(Icons.cloud_outlined, size: 14, color: syncDotColor),
              ],
            ),
          ),
        ),
        IconButton(icon: Icon(Icons.search, color: fgCol), onPressed: () => setState(() => _isSearching = true)),
        IconButton(icon: Icon(Icons.shield_outlined, color: fgCol), onPressed: () => context.push('/vault')),
        IconButton(icon: Icon(Icons.dashboard_customize, color: fgCol), onPressed: () => setState(() => _isEditMode = true)),
        Consumer(
          builder: (context, ref, _) {
            final isPrivacy = ref.watch(privacyModeProvider);
            return IconButton(
              icon: Icon(isPrivacy ? Icons.visibility : Icons.visibility_off_outlined, color: fgCol),
              tooltip: isPrivacy ? 'Privacy Mode: Active (Figures masked)' : 'Privacy Mode: Inactive (Click to mask)',
              onPressed: () {
                ref.read(privacyModeProvider.notifier).toggle();
                final newState = !isPrivacy;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(newState ? 'Privacy Mode Enabled: Figures masked 🛡️' : 'Privacy Mode Disabled: Figures revealed 👁️'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            );
          },
        ),
        IconButton(icon: Icon(Icons.download, color: fgCol), onPressed: _exportCsv),
        IconButton(icon: Icon(Icons.settings, color: fgCol), onPressed: () => _showSettingsPanel(context)),
      ].animate(interval: 30.ms).fadeIn(duration: 200.ms).slideY(begin: 0.1, duration: 200.ms);
    }
    return [IconButton(icon: Icon(Icons.check, color: fgCol), onPressed: () => FocusManager.instance.primaryFocus?.unfocus())];
  }

  Widget _buildBottomNav(ColorScheme colorScheme) {
    final isVlmActive = ref.watch(isVlmReadyProvider);
    final isLlmActive = ref.watch(isLlmLoadedProvider);
    final isAiActive = isVlmActive || isLlmActive;

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
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isVlmActive ? const Color(0xFF10B981) : (isLlmActive ? const Color(0xFF0891B2) : Colors.grey),
                      boxShadow: isAiActive ? [
                        BoxShadow(
                          color: (isVlmActive ? const Color(0xFF10B981) : const Color(0xFF0891B2)).withOpacity(0.5),
                          blurRadius: 8,
                        )
                      ] : null,
                    ),
                  )
                      .animate(target: isAiActive ? 1 : 0, onPlay: (c) => isAiActive ? c.repeat(reverse: true) : null)
                      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 1.seconds),
                  const SizedBox(width: 8),
                  Text(
                    isVlmActive ? 'VLM Core Active' : (isLlmActive ? 'OCR Core Active' : 'AI Offline'),
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            InteractiveHover(
              onTap: () => context.push('/scan'),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
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
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => const SettingsPanelWidget(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}
