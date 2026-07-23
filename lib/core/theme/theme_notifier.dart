import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

// Persisted theme notifier — reads/writes from the shared Hive 'settings' box
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final Box _box;
  static const _key = 'theme_mode'; // 'light' | 'dark' | 'system'

  ThemeNotifier(this._box)
      : super(_parse(_box.get(_key, defaultValue: 'light')));

  static ThemeMode _parse(String val) {
    switch (val) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  bool get isDark => state == ThemeMode.dark;

  void setLight() => _set(ThemeMode.light, 'light');
  void setDark() => _set(ThemeMode.dark, 'dark');
  void toggle() => isDark ? setLight() : setDark();

  void _set(ThemeMode mode, String val) {
    _box.put(_key, val);
    state = mode;
  }
}

// Provider — overridden in main.dart with the real settingsBox
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  throw UnimplementedError('themeProvider must be overridden in main.dart');
});
