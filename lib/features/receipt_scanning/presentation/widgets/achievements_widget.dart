// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/gamification_service.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AchievementsWidget extends StatelessWidget {
  final List<Achievement> achievements;

  const AchievementsWidget({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'BADGES & MILESTONES',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: achievements.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
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
