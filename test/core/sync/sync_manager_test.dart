import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sync Conflict Resolution Rules (LWW + Monotonic Versioning)', () {
    test('higher version always overwrites lower version regardless of timestamp', () {
      final localVersion = 1;
      final remoteVersion = 2;
      final localUpdated = DateTime.now();
      final remoteUpdated = DateTime.now().subtract(const Duration(minutes: 5));

      // Remote has higher version (2 > 1) -> remote should overwrite
      final shouldOverwrite = remoteVersion > localVersion ||
          (remoteVersion == localVersion && remoteUpdated.isAfter(localUpdated));
      expect(shouldOverwrite, true);
    });

    test('lower version never overwrites higher version', () {
      final localVersion = 3;
      final remoteVersion = 2;

      final shouldOverwrite = remoteVersion > localVersion;
      expect(shouldOverwrite, false);
    });

    test('equal versions resolve using Last-Write-Wins (LWW) server timestamp', () {
      final localVersion = 2;
      final remoteVersion = 2;
      final localUpdated = DateTime(2026, 8, 28, 14, 0, 0);
      final remoteUpdated = DateTime(2026, 8, 28, 14, 05, 0); // newer

      final shouldOverwrite = (remoteVersion > localVersion) ||
          (remoteVersion == localVersion && remoteUpdated.isAfter(localUpdated));

      expect(shouldOverwrite, true);
    });

    test('equal versions with older remote timestamp do not overwrite', () {
      final localVersion = 2;
      final remoteVersion = 2;
      final localUpdated = DateTime(2026, 8, 28, 14, 10, 0);
      final remoteUpdated = DateTime(2026, 8, 28, 14, 05, 0); // older

      final shouldOverwrite = (remoteVersion > localVersion) ||
          (remoteVersion == localVersion && remoteUpdated.isAfter(localUpdated));

      expect(shouldOverwrite, false);
    });
  });
}
