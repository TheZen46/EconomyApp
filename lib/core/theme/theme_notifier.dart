import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';

// Persisted theme notifier — reads/writes from the shared Hive 'settings' box
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final Box? _box;
  static const _key = 'theme_mode'; // 'light' | 'dark' | 'system'

  ThemeNotifier([this._box])
      : super(_parse(_box?.get(_key, defaultValue: 'dark') ?? 'dark'));

  static ThemeMode _parse(String val) {
    switch (val) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  bool get isDark => state == ThemeMode.dark;

  void setLight() => _set(ThemeMode.light, 'light');
  void setDark() => _set(ThemeMode.dark, 'dark');
  void toggle() => isDark ? setLight() : setDark();

  void _set(ThemeMode mode, String val) {
    _box?.put(_key, val);
    state = mode;
  }
}

// Provider — safely falls back to ThemeMode.dark if settingsBox is missing
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return ThemeNotifier(box);
  } catch (_) {
    return ThemeNotifier(null);
  }
});

// Balatro Easter Egg Theme Notifier
class BalatroThemeNotifier extends StateNotifier<bool> {
  BalatroThemeNotifier() : super(false);

  static const double threshold = 4.6e46;
  static final RegExp malformedRegex = RegExp(r'^\s*(\d+(?:\.\d+)?)\+e([+-]?\d+)\s*$', caseSensitive: false);

  bool checkTrigger(dynamic input) {
    if (input == null) return false;
    final str = input.toString().trim();
    if (str.isEmpty) return false;

    // 1. Check exact trigger or malformed scientific notation (56+e2)
    if (str.toLowerCase() == '56+e2' || malformedRegex.hasMatch(str)) {
      state = true;
      return true;
    }

    // 2. Check numeric value >= 4.6e+46
    final numVal = double.tryParse(str);
    if (numVal != null && numVal >= threshold) {
      state = true;
      return true;
    }

    return false;
  }

  void enable() => state = true;
  void disable() => state = false;
  void toggle() => state = !state;
}

final isBalatroThemeProvider = StateNotifierProvider<BalatroThemeNotifier, bool>((ref) {
  return BalatroThemeNotifier();
});

