import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // PostgreSQL regular expressions read \b as a backspace character, not as a
  // word boundary (\y), so a pattern containing it silently never matches.
  test('SQL files do not use \\b in regular expressions', () {
    final sqlFiles = Directory('supabase')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'));
    expect(sqlFiles, isNotEmpty);

    final offending = <String>[];
    for (final file in sqlFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('--').first;
        if (code.contains(r'\b')) offending.add('${file.path}:${i + 1}');
      }
    }
    expect(offending, isEmpty);
  });
}
