import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../providers/storage_providers.dart';

/// State notifier managing the application's active [ThemeMode] (light, dark, or system).
///
/// Persists the selected mode to the shared Hive `settings` box under the key `theme_mode`.
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final Box? _box;
  static const _key = 'theme_mode'; // 'light' | 'dark' | 'system'

  /// Creates a [ThemeNotifier] using the optional persistent [Box].
  ///
  /// Defaults to [ThemeMode.dark] if the box is missing or unset.
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

  /// Whether the current active theme mode is [ThemeMode.dark].
  bool get isDark => state == ThemeMode.dark;

  /// Sets the application theme to [ThemeMode.light] and persists the preference.
  void setLight() => _set(ThemeMode.light, 'light');

  /// Sets the application theme to [ThemeMode.dark] and persists the preference.
  void setDark() => _set(ThemeMode.dark, 'dark');

  /// Toggles between light and dark theme modes.
  void toggle() => isDark ? setLight() : setDark();

  void _set(ThemeMode mode, String val) {
    _box?.put(_key, val);
    state = mode;
  }
}

/// Provides the active [ThemeMode] across the application shell.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `settingsBoxProvider`.
/// **Override:** Optional in tests. Falls back gracefully to [ThemeMode.dark] if settings box is missing.
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  try {
    final box = ref.watch(settingsBoxProvider);
    return ThemeNotifier(box);
  } catch (_) {
    return ThemeNotifier(null);
  }
});

/// State notifier controlling the Balatro easter egg theme state.
///
/// Activated when numeric transaction inputs trigger scientific notation anomalies
/// or cross the 4.6e46 threshold.
class BalatroThemeNotifier extends StateNotifier<bool> {
  BalatroThemeNotifier() : super(false);

  /// Threshold value above which the Balatro easter egg is triggered.
  static const double threshold = 4.6e46;

  /// Regular expression detecting malformed scientific notation triggers (e.g. `56+e2`).
  static final RegExp malformedRegex = RegExp(r'^\s*(\d+(?:\.\d+)?)\+e([+-]?\d+)\s*$', caseSensitive: false);

  /// Checks if [input] satisfies easter egg triggers and activates the theme if so.
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

  /// Activates the Balatro easter egg theme.
  void enable() => state = true;

  /// Deactivates the Balatro easter egg theme.
  void disable() => state = false;

  /// Toggles the Balatro easter egg theme state.
  void toggle() => state = !state;
}

/// Provides the active state of the Balatro easter egg theme.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** None.
final isBalatroThemeProvider = StateNotifierProvider<BalatroThemeNotifier, bool>((ref) {
  return BalatroThemeNotifier();
});

