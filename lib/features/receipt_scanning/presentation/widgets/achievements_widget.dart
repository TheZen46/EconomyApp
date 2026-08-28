import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/gamification_service.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AchievementsWidget extends StatelessWidget {
  final List<Achievement> achievements;

  const AchievementsWidget({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    final unlockedCount = achievements.where((a) => a.isUnlocked).length;
    final totalXp = (achievements.length * 50) + (unlockedCount * 100);
    const xpPerLevel = 300;
    final currentLevel = (totalXp ~/ xpPerLevel) + 1;
    final xpInCurrentLevel = totalXp % xpPerLevel;
    final levelProgress = (xpInCurrentLevel / xpPerLevel).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BADGES & MILESTONES',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '$unlockedCount/${achievements.length}',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // XP Progress Section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outline.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LVL $currentLevel',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'XP Progress',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$xpInCurrentLevel / $xpPerLevel XP',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: levelProgress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: achievements.length,
            separatorBuilder: (ctx, i) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = achievements[index];
              return _AchievementCard(item: item)
                  .animate()
                  .slideX(begin: 0.2, end: 0, delay: (index * 100).ms, curve: Curves.easeOutQuart)
                  .fadeIn(delay: (index * 100).ms);
            },
          ),
        ),
      ],
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement item;

  const _AchievementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${item.name}\n${item.description}',
      triggerMode: TooltipTriggerMode.tap,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      textStyle: const TextStyle(color: AppTheme.textMain),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.isUnlocked 
              ? item.color.withAlpha(38) 
              : Colors.white.withAlpha(7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isUnlocked 
                ? item.color.withAlpha(127) 
                : Colors.white.withAlpha(25),
          ),
          boxShadow: item.isUnlocked ? [
            BoxShadow(color: item.color.withAlpha(51), blurRadius: 10, offset: const Offset(0,4))
          ] : null
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 32,
              color: item.isUnlocked ? item.color : Colors.white24,
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: item.isUnlocked ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: item.isUnlocked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
