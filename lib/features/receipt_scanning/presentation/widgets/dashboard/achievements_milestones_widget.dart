import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/services/gamification_service.dart';
import '../../../domain/entities/receipt.dart';
import '../../../../boxes/data/models/box_model.dart';
import '../../../../boxes/data/providers/boxes_provider.dart';
import 'gamification_header.dart';

/// Interactive dashboard widget displaying gamified milestones, XP, and unlockable badges.
class AchievementsMilestonesWidget extends ConsumerWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const AchievementsMilestonesWidget({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;

    final boxes = ref.watch(boxesProvider);
    final activeId = ref.watch(activeBoxIdProvider);
    final activeBox = activeId == 'main' || boxes.isEmpty
        ? (boxes.isNotEmpty
            ? boxes.first
            : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0))
        : boxes.firstWhere(
            (b) => b.id == activeId,
            orElse: () => boxes.isNotEmpty
                ? boxes.first
                : BoxModel(id: 'main', name: 'Main', budget: 0, spent: 0, currency: 'USD', color: 0),
          );

    final achievements = GamificationService.calculateAchievements(
      receipts,
      activeBox.budget,
    );

    final unlockedCount = achievements.where((a) => a.isUnlocked).length;
    final totalCount = achievements.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MILESTONES & XP',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                letterSpacing: 1.2,
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Text(
                '$unlockedCount/$totalCount',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: unlockedCount > 0 ? accent : muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GamificationHeader(
          receipts: receipts,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        ...achievements.take(3).map((achievement) {
          final isUnlocked = achievement.isUnlocked;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isUnlocked ? achievement.color : colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  achievement.icon,
                  size: 18,
                  color: isUnlocked ? achievement.color : muted.withAlpha(120),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievement.name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: fgCol,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        achievement.description,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isUnlocked ? achievement.color.withAlpha(25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isUnlocked ? 'Unlocked' : 'Locked',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? achievement.color : muted.withAlpha(150),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
