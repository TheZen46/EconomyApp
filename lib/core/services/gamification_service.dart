import 'package:flutter/material.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

class Achievement {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool isUnlocked;
  final Color color;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.isUnlocked,
    required this.color,
  });
}

class GamificationService {
  static List<Achievement> calculateAchievements(List<Receipt> receipts, double monthlyBudget) {
    return [
      _checkFirstScan(receipts),
      _checkStreak(receipts, 3),  // 3 Day Streak
      _checkBudgetNinja(receipts, monthlyBudget),
      _checkDataHoarder(receipts, 10), // 10 Receipts
      _checkNightOwl(receipts), // Scan after 10PM
    ];
  }

  static Achievement _checkFirstScan(List<Receipt> receipts) {
    final unlocked = receipts.isNotEmpty;
    return Achievement(
      id: 'first_scan',
      name: 'First Step',
      description: 'Scan your first receipt',
      icon: Icons.flag,
      isUnlocked: unlocked,
      color: Colors.blueAccent,
    );
  }

  static Achievement _checkStreak(List<Receipt> receipts, int days) {
    if (receipts.isEmpty) return _locked('Streak Fire', 'Scan for $days days in a row', Icons.local_fire_department, Colors.orangeAccent);
    
    // Sort desc
    final sorted = List<Receipt>.from(receipts)..sort((a, b) => b.date.compareTo(a.date));
    int streak = 0;
    
    // Normalize dates to remove time
    DateTime toDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    
    // Check from today/yesterday backwards
    DateTime currentCheck = toDate(DateTime.now());
    
    // If no receipt today, check if streak ended yesterday
    // Optimistic: We just count unique days in sequence
    // Simplified: Just count max consecutive days in usage history?
    // Or just current streak? "Scan 3 days in a row" implies active streak or historical max?
    // Let's do: Has EVER had a streak of N days.
    
    // Set of unique days
    final uniqueDays = sorted.map((r) => toDate(r.date)).toSet().toList()..sort((a,b) => b.compareTo(a));
    
    int maxStreak = 0;
    int currentRun = 0;
    
    for (int i = 0; i < uniqueDays.length - 1; i++) {
       currentRun++;
       final diff = uniqueDays[i].difference(uniqueDays[i+1]).inDays;
       if (diff == 1) {
         // continued
       } else {
         if (currentRun > maxStreak) maxStreak = currentRun;
         currentRun = 0;
       }
    }
    if (currentRun > maxStreak) maxStreak = currentRun;
    // Add 1 for the last item if list not empty
    if (uniqueDays.isNotEmpty && maxStreak == 0) maxStreak = 1;

    return Achievement(
      id: 'streak_$days',
      name: 'Streak Fire',
      description: 'Scan for $days days in a row',
      icon: Icons.local_fire_department,
      isUnlocked: maxStreak >= days,
      color: Colors.orangeAccent,
    );
  }

  static Achievement _checkBudgetNinja(List<Receipt> receipts, double budget) {
    // Check purely if current month spent < budget? 
    // Only valid if month is over? Or if we have data for a full month?
    // Let's make it easier: "Under Budget" -> Current month usage < 80% (Safe buffer)
    if (receipts.isEmpty) return _locked('Budget Ninja', 'Stay under 80% of budget', Icons.security, Colors.greenAccent);
    
    final now = DateTime.now();
    final monthSum = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .fold(0.0, (sum, item) => sum + item.totalAmount);
        
    final isUnlocked = budget > 0 && monthSum < (budget * 0.8) && monthSum > 0;
    
    return Achievement(
      id: 'budget_ninja',
      name: 'Budget Ninja',
      description: 'Keep monthly spend under 80%',
      icon: Icons.security,
      isUnlocked: isUnlocked,
      color: Colors.greenAccent,
    );
  }

  static Achievement _checkDataHoarder(List<Receipt> receipts, int count) {
    return Achievement(
      id: 'hoarder',
      name: 'Data Hoarder',
      description: 'Collect $count+ receipts',
      icon: Icons.storage,
      isUnlocked: receipts.length >= count,
      color: Colors.purpleAccent,
    );
  }
  
  static Achievement _checkNightOwl(List<Receipt> receipts) {
    // Scan receipt after 10PM (22:00)
    final hasLateScan = receipts.any((r) => r.date.hour >= 22 || r.date.hour < 4);
    
     return Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Scan a receipt after 10 PM',
      icon: Icons.nights_stay,
      isUnlocked: hasLateScan,
      color: Colors.indigoAccent,
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
