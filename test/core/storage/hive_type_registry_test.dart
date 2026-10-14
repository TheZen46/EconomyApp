import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hive identifies stored objects by typeId. Two types sharing one id corrupt
/// each other's records, so every id must be claimed by exactly one type,
/// whether through a @HiveType annotation or a hand-written TypeAdapter.
void main() {
  test('every Hive typeId in lib/ belongs to exactly one type', () {
    final annotated = RegExp(r'@HiveType\(typeId:\s*(\d+)\)\s*(?:///[^\n]*\n\s*)*(?:class|enum)\s+(\w+)');
    final adapter = RegExp(r'class\s+\w+\s+extends\s+TypeAdapter<(\w+)>\s*\{[^}]*?typeId\s*=\s*(\d+)', dotAll: true);

    final owners = <int, Set<String>>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final m in annotated.allMatches(source)) {
        owners.putIfAbsent(int.parse(m.group(1)!), () => {}).add(m.group(2)!);
      }
      for (final m in adapter.allMatches(source)) {
        owners.putIfAbsent(int.parse(m.group(2)!), () => {}).add(m.group(1)!);
      }
    }

    expect(owners, isNotEmpty);
    final collisions = {
      for (final entry in owners.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };
    expect(collisions, isEmpty, reason: 'typeIds claimed by more than one type');
    expect(owners[12], {'SyncOutboxItem'});
  });
}
