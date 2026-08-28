import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/login_form.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final fg = isDark ? AppColors.darkFg : AppColors.lightFg;
    final muted = isDark ? AppColors.darkFgDim : AppColors.lightMuted;

    // Listen for error messages
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: next.errorMessage!.contains('Check your email')
                ? AppColors.accent
                : AppColors.destructive,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo ────────────────────────────────────────────
                Icon(Icons.receipt_long, size: 64, color: AppColors.accent)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(begin: const Offset(0.8, 0.8)),
                const SizedBox(height: 16),
                Text(
                  'tAIdy',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ).animate().fadeIn(delay: 100.ms),
                Text(
                  'Privacy-First Expense Tracker',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    color: muted,
                  ),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 48),

                // ── Auth Form Card ──────────────────────────────────
                const LoginForm()
                    .animate()
                    .fadeIn(delay: 300.ms)
                    .slideY(begin: 0.05),

                const SizedBox(height: 24),
                Text(
                  'Your data stays on your device. Always.',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    color: muted.withAlpha(128),
                  ),
                ).animate().fadeIn(delay: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
