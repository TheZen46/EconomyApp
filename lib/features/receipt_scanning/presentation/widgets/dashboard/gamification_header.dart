import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../domain/entities/receipt.dart';
import '../../../../../core/services/gamification_service.dart';

class GamificationHeader extends ConsumerWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const GamificationHeader({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final achievements = GamificationService.calculateAchievements(receipts, 1000);
    final unlockedCount = achievements.where((a) => a.isUnlocked).length;
    final totalXp = (receipts.length * 50) + (unlockedCount * 100);
    const xpPerLevel = 300;
    final currentLevel = (totalXp ~/ xpPerLevel) + 1;
    final xpInCurrentLevel = totalXp % xpPerLevel;
    final levelProgress = (xpInCurrentLevel / xpPerLevel).clamp(0.0, 1.0);

    final streakAchievement = achievements.firstWhere(
      (a) => a.id.startsWith('streak'),
      orElse: () => Achievement(id: '', name: '', description: '', icon: Icons.local_fire_department, isUnlocked: false, color: Colors.orange),
    );
    final isStreakActive = streakAchievement.isUnlocked || receipts.isNotEmpty;
    final streakDays = receipts.isEmpty ? 0 : (streakAchievement.isUnlocked ? 3 : 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'LVL $currentLevel',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'XP Progress',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: fgCol,
                      ),
                    ),
                    Text(
                      '$xpInCurrentLevel / $xpPerLevel XP',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: levelProgress,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isStreakActive
                  ? Colors.orange.withAlpha(30)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isStreakActive ? Colors.orange : colorScheme.outline.withAlpha(50),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 14,
                  color: isStreakActive ? Colors.orange : muted,
                ),
                const SizedBox(width: 4),
                Text(
                  '$streakDays d',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isStreakActive ? Colors.orange : muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.05);
  }
}
