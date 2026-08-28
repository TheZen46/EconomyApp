import 'dart:math';

class StringUtils {
  /// Calculates the Levenshtein distance between two strings.
  /// Lower distance means more similar.
  static int levenshtein(String s, String t, {bool caseInsensitive = true}) {
    if (caseInsensitive) {
      s = s.toLowerCase();
      t = t.toLowerCase();
    }
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  /// Returns true if [query] matches [text] with a tolerance of [tolerance] edits.
  /// Also returns true if [text] contains [query] as a substring (ignoring tolerance).
  static bool fuzzyMatch(String query, String text, {int tolerance = 2}) {
    if (query.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    final normalizedText = text.toLowerCase();
    
    // 1. Direct Substring (Fastest & most common)
    if (normalizedText.contains(normalizedQuery)) return true;
    
    // 2. Fuzzy Match (Levenshtein)
    // Only try fuzzy if query is at least 3 chars to avoid noise
    if (normalizedQuery.length < 3) return false;
    
    return levenshtein(normalizedQuery, normalizedText) <= tolerance;
  }
}
