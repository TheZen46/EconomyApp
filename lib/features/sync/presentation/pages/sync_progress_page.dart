import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/sync_progress_state.dart';
import '../providers/sync_provider.dart';
import '../widgets/kinetic_sync_progress_bar.dart';

/// Dedicated, immersive synchronization page that blocks workspace interaction
/// while cloud data replication and delta syncing take place.
class SyncProgressPage extends ConsumerStatefulWidget {
  const SyncProgressPage({super.key});

  @override
  ConsumerState<SyncProgressPage> createState() => _SyncProgressPageState();
}

class _SyncProgressPageState extends ConsumerState<SyncProgressPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerSync();
    });
  }

  void _triggerSync() {
    final authState = ref.read(authProvider);
    String userId = authState.user?.id ?? '';
    if (userId.isEmpty) {
      try {
        userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      } catch (_) {}
    }

    if (userId.isNotEmpty) {
      ref.read(syncProgressProvider.notifier).startInitialSync(userId);
    } else {
      // Local/offline unauthenticated session
      ref.read(initialSyncCompletedProvider.notifier).state = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          _navigateOut();
        }
      });
    }
  }

  void _navigateOut() {
    ref.read(initialSyncCompletedProvider.notifier).state = true;
    if (context.canPop()) {
      context.pop();
    } else {
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      if (from != null &&
          from.isNotEmpty &&
          from != AppRoutes.syncProgress &&
          from != AppRoutes.login &&
          from != AppRoutes.root) {
        context.go(from);
      } else {
        context.go(AppRoutes.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final fg = isDark ? AppColors.darkFg : AppColors.lightFg;
    final muted = isDark ? AppColors.darkFgDim : AppColors.lightMuted;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final syncState = ref.watch(syncProgressProvider);
    final authState = ref.watch(authProvider);
    String userId = authState.user?.id ?? '';
    if (userId.isEmpty) {
      try {
        userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      } catch (_) {}
    }

    // Auto-navigate after a brief completion confirmation
    ref.listen<SyncProgressState>(syncProgressProvider, (prev, next) {
      if (next.isCompleted && prev?.stage != SyncStage.completed) {
        ref.read(initialSyncCompletedProvider.notifier).state = true;
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _navigateOut();
          }
        });
      }
    });

    final canExit = context.canPop() || ref.watch(initialSyncCompletedProvider) || syncState.isCompleted;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: canExit
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: fg),
                onPressed: _navigateOut,
                tooltip: 'Back to App',
              )
            : null,
        actions: [
          if (canExit)
            TextButton(
              onPressed: _navigateOut,
              child: Text(
                'Close',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Brand Header & Quantum Orb ─────────────────────────────
                  _buildQuantumLogo(isDark, syncState.isCompleted)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(begin: const Offset(0.85, 0.85)),

                  const SizedBox(height: 24),

                  Text(
                    syncState.isCompleted
                        ? 'Replication Complete'
                        : 'Replicating Environment',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: fg,
                    ),
                  ).animate().fadeIn(delay: 150.ms),

                  const SizedBox(height: 6),

                  Text(
                    syncState.isCompleted
                        ? 'Your local database is fully synchronized.'
                        : 'Cross-Device Encrypted Data Synchronization',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: muted,
                    ),
                  ).animate().fadeIn(delay: 250.ms),

                  const SizedBox(height: 32),

                  // ── Main Telemetry & Visualizer Card ───────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.4 : 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Kinetic Flowing Progress Bar
                        KineticSyncProgressBar(
                          progress: syncState.progress,
                          isDark: isDark,
                          speedLabel: syncState.transferSpeedBytesPerSec > 0
                              ? syncState.formattedSpeed
                              : null,
                        ),

                        const SizedBox(height: 24),

                        // Dynamic Context-Aware Message Banner
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.15),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Container(
                            key: ValueKey(syncState.message),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.black.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : Colors.black.withOpacity(0.04),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  syncState.isCompleted
                                      ? Icons.check_circle_outline_rounded
                                      : syncState.isFailed
                                          ? Icons.warning_amber_rounded
                                          : syncState.isRetrying
                                              ? Icons.sync_problem_rounded
                                              : Icons.cloud_sync_outlined,
                                  size: 18,
                                  color: syncState.isCompleted
                                      ? const Color(0xFF10B981)
                                      : syncState.isFailed
                                          ? AppColors.destructive
                                          : syncState.isRetrying
                                              ? Colors.amber
                                              : AppColors.accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    syncState.message,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: syncState.isCompleted
                                          ? const Color(0xFF10B981)
                                          : syncState.isFailed
                                              ? AppColors.destructive
                                              : fg,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 20),

                        // Telemetry Grid
                        _buildTelemetryGrid(syncState, isDark, fg, muted),
                      ],
                    ),
                  ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.05),

                  const SizedBox(height: 24),

                  // ── Action Buttons & Error Recovery ────────────────────────
                  if (syncState.isCompleted) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _navigateOut,
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: Text(
                          'Enter Workspace',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ).animate().fadeIn().scale(),
                  ] else if (syncState.isFailed || syncState.isRetrying || syncState.canContinueOffline) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              ref
                                  .read(syncProgressProvider.notifier)
                                  .continueOffline();
                              _navigateOut();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: cardBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Continue Offline',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              ref
                                  .read(syncProgressProvider.notifier)
                                  .retry(userId);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Retry Sync',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(),
                  ] else ...[
                    // Subtle hint text with manual offline bypass
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: muted.withOpacity(0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '256-bit AES encryption',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: muted.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            ref
                                .read(syncProgressProvider.notifier)
                                .continueOffline();
                            _navigateOut();
                          },
                          child: Text(
                            'Skip to App',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 500.ms),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuantumLogo(bool isDark, bool isCompleted) {
    final ringColor = isCompleted ? const Color(0xFF10B981) : AppColors.accent;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: ringColor.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ringColor.withOpacity(0.25),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          isCompleted ? Icons.check_rounded : Icons.sync_rounded,
          size: 36,
          color: ringColor,
        ),
      ),
    );
  }

  Widget _buildTelemetryGrid(
    SyncProgressState state,
    bool isDark,
    Color fg,
    Color muted,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTelemetryMetric(
                label: 'DATA REPLICATED',
                value: state.formattedBytes,
                subvalue: state.totalBytes > 0
                    ? '/ ${(state.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                    : null,
                fg: fg,
                muted: muted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTelemetryMetric(
                label: 'DELTA OBJECTS',
                value: '${state.itemsCompleted}',
                subvalue: '/ ${state.totalItems > 0 ? state.totalItems : 1}',
                fg: fg,
                muted: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTelemetryMetric(
                label: 'BANDWIDTH',
                value: state.formattedSpeed,
                fg: fg,
                muted: muted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTelemetryMetric(
                label: 'ESTIMATED TIME',
                value: state.formattedEta,
                fg: fg,
                muted: muted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTelemetryMetric({
    required String label,
    required String value,
    String? subvalue,
    required Color fg,
    required Color muted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
            color: muted,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
            if (subvalue != null) ...[
              const SizedBox(width: 4),
              Text(
                subvalue,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: muted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
