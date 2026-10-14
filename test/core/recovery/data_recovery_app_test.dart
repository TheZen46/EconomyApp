import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/recovery/data_recovery_app.dart';
import 'package:t_aidy/core/services/hive_migration_service.dart';

void main() {
  testWidgets('starting over quarantines the failed box after confirmation', (tester) async {
    final quarantined = <List<String>>[];
    await tester.pumpWidget(DataRecoveryApp(
      recovery: StartupRecovery.unreadableBox(
        SchemaCorruptionException(boxName: 'receipts_v3', cause: 'bad frame', backupPath: '/backups/receipts.hive'),
      ),
      quarantine: (boxes) async {
        quarantined.add(boxes);
        return '/backups/quarantine_1';
      },
    ));

    expect(find.text('Data Recovery Required'), findsOneWidget);
    expect(find.text('/backups/receipts.hive'), findsOneWidget);

    await tester.tap(find.text('Start with an empty database'));
    await tester.pumpAndSettle();
    expect(quarantined, isEmpty, reason: 'nothing is moved before confirmation');

    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();

    expect(quarantined, [
      ['receipts_v3'],
    ]);
    expect(find.textContaining('open it again'), findsOneWidget);
    expect(find.text('/backups/quarantine_1'), findsOneWidget);
  });

  testWidgets('a lost encryption key offers to start over for every encrypted box', (tester) async {
    final quarantined = <List<String>>[];
    await tester.pumpWidget(DataRecoveryApp(
      recovery: StartupRecovery.encryptionKeyLost(const ['receipts_v3', 'sync_outbox']),
      quarantine: (boxes) async {
        quarantined.add(boxes);
        return null;
      },
    ));

    expect(find.text('Encryption Key Not Found'), findsOneWidget);
    await tester.tap(find.text('Start with an empty database'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();

    expect(quarantined.single, ['receipts_v3', 'sync_outbox']);
  });

  testWidgets('unavailable secure storage offers no reset, since it would not help', (tester) async {
    await tester.pumpWidget(DataRecoveryApp(
      recovery: StartupRecovery.secureStorageUnavailable(Exception('keyring locked')),
      quarantine: (_) async => fail('must not quarantine'),
    ));

    expect(find.text('Secure Storage Unavailable'), findsOneWidget);
    expect(find.text('Start with an empty database'), findsNothing);
  });
}
