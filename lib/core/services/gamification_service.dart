import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

/// Represents a gamified milestone or behavioral badge in the tAIdy platform.
class Achievement {
  /// Unique identifier of the achievement.
  final String id;

  /// User-facing display title.
  final String name;

  /// Detailed description of unlocking criteria.
  final String description;

  /// Material icon visualizing the badge.
  final IconData icon;

  /// Whether the user has met all criteria to unlock this badge.
  final bool isUnlocked;

  /// Theme accent color associated with the badge.
  final Color color;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.isUnlocked,
    required this.color,
  });
}

/// Service calculating financial gamification achievements, streaks, and milestone progression.
class GamificationService {
  /// Evaluates all behavioral badges against the user's historical [receipts] and [monthlyBudget].
  static List<Achievement> calculateAchievements(
    List<Receipt> receipts,
    double monthlyBudget, {
    bool isBalatro = false,
  }) {
    return [
      _checkFirstScan(receipts),
      _checkStreak(receipts, AppConstants.streakAchievementDays),
      _checkBudgetNinja(receipts, monthlyBudget),
      _checkDataHoarder(receipts, AppConstants.dataHoarderCountThreshold),
      _checkNightOwl(receipts),
      _checkJokersGambit(isBalatro),
    ];
  }

  /// Evaluates the Balatro easter egg reality badge.
  static Achievement _checkJokersGambit(bool isUnlocked) {
    return Achievement(
      id: 'jokers_gambit',
      name: "Joker's Gambit 🃏",
      description: 'Bent reality with an astronomical input (+500 XP / +10k Chips)',
      icon: Icons.casino,
      isUnlocked: isUnlocked,
      color: const Color(0xFFFF3333),
    );
  }

  /// Evaluates the First Step onboarding milestone.
  static Achievement _checkFirstScan(List<Receipt> receipts) {
    final unlocked = receipts.isNotEmpty;
    return Achievement(
      id: 'first_scan',
      name: 'First Step',
      description: 'Scan your first receipt',
      icon: Icons.flag,
      isUnlocked: unlocked,
      color: AppColors.accent,
    );
  }

  /// Calculates current active streak in consecutive calendar days up to today or yesterday.
  static int calculateCurrentStreak(List<Receipt> receipts) {
    if (receipts.isEmpty) return 0;

    DateTime toDateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    final uniqueDays = receipts
        .map((r) => toDateOnly(r.date))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (uniqueDays.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // If latest receipt date is older than yesterday, streak is broken
    final latestDate = uniqueDays.first;
    if (latestDate.isBefore(yesterday)) {
      return 0;
    }

    int streak = 1;
    for (int i = 0; i < uniqueDays.length - 1; i++) {
      final diff = uniqueDays[i].difference(uniqueDays[i + 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Evaluates consecutive scanning day streak history.
  static Achievement _checkStreak(List<Receipt> receipts, int days) {
    if (receipts.isEmpty) {
      return _locked(
        'Streak Fire',
        'Scan for $days days in a row',
        Icons.local_fire_department,
        const Color(0xFFF97316),
      );
    }

    final sorted = List<Receipt>.from(receipts)
      ..sort((a, b) => b.date.compareTo(a.date));

    DateTime toDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    final uniqueDays = sorted.map((r) => toDate(r.date)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    int maxStreak = 0;
    int currentRun = 0;

    for (int i = 0; i < uniqueDays.length - 1; i++) {
      currentRun++;
      final diff = uniqueDays[i].difference(uniqueDays[i + 1]).inDays;
      if (diff == 1) {
        // Continuous consecutive day
      } else {
        if (currentRun > maxStreak) maxStreak = currentRun;
        currentRun = 0;
      }
    }
    if (currentRun > maxStreak) maxStreak = currentRun;
    if (uniqueDays.isNotEmpty && maxStreak == 0) maxStreak = 1;

    return Achievement(
      id: 'streak_$days',
      name: 'Streak Fire',
      description: 'Scan for $days days in a row',
      icon: Icons.local_fire_department,
      isUnlocked: maxStreak >= days,
      color: const Color(0xFFF97316),
    );
  }

  /// Evaluates whether monthly spending is within a healthy buffer ratio of the budget.
  static Achievement _checkBudgetNinja(List<Receipt> receipts, double budget) {
    if (receipts.isEmpty || budget <= 0) {
      return _locked(
        'Budget Ninja',
        'Stay under ${(AppConstants.budgetNinjaSafeRatio * 100).toInt()}% of budget',
        Icons.security,
        const Color(0xFF10B981),
      );
    }

    final now = DateTime.now();
    final monthSum = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, item) => sum + item.totalAmount);

    final isUnlocked = monthSum < (budget * AppConstants.budgetNinjaSafeRatio) && monthSum > 0;

    return Achievement(
      id: 'budget_ninja',
      name: 'Budget Ninja',
      description: 'Keep monthly spend under ${(AppConstants.budgetNinjaSafeRatio * 100).toInt()}%',
      icon: Icons.security,
      isUnlocked: isUnlocked,
      color: const Color(0xFF10B981),
    );
  }

  /// Evaluates whether user has collected [count] or more receipts.
  static Achievement _checkDataHoarder(List<Receipt> receipts, int count) {
    return Achievement(
      id: 'hoarder',
      name: 'Data Hoarder',
      description: 'Collect $count+ receipts',
      icon: Icons.storage,
      isUnlocked: receipts.length >= count,
      color: const Color(0xFF8B5CF6),
    );
  }

  /// Evaluates whether user scanned any receipt during late evening hours.
  static Achievement _checkNightOwl(List<Receipt> receipts) {
    final hasLateScan = receipts.any(
      (r) => r.date.hour >= AppConstants.nightOwlHourThreshold || r.date.hour < 4,
    );

    return Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Scan a receipt after ${AppConstants.nightOwlHourThreshold - 12} PM',
      icon: Icons.nights_stay,
      isUnlocked: hasLateScan,
      color: const Color(0xFF6366F1),
    );
  }

  static Achievement _locked(String name, String desc, IconData icon, Color color) {
    return Achievement(
      id: 'locked',
      name: name,
      description: desc,
      icon: icon,
      isUnlocked: false,
      color: color,
    );
  }
}
