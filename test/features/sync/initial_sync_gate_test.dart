import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:t_aidy/core/privacy/network_policy.dart';
import 'package:t_aidy/core/providers/supabase_providers.dart';
import 'package:t_aidy/features/auth/presentation/providers/auth_provider.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/hive_receipt_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';
import 'package:t_aidy/features/sync/data/datasources/remote_replica_data_source.dart';
import 'package:t_aidy/features/sync/presentation/providers/sync_provider.dart';


/// A cloud account with no data.
class _EmptyRemote implements RemoteReplicaDataSource {
  @override
  Future<List<RemoteFileEntry>> listRemoteFiles(String userId) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(<Map<String, dynamic>>[]);
}

class _CountingRemote implements RemoteReplicaDataSource {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return Future.value(<Map<String, dynamic>>[]);
  }
}

class _EmptyLocal implements LocalReceiptDataSource {
  @override
  Future<List<ReceiptModel>> getReceipts() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeAuth extends StateNotifier<AppAuthState> implements AuthNotifier {
  _FakeAuth(String? userId)
      : super(userId == null
            ? const AppAuthState()
            : AppAuthState(
                status: AuthStatus.authenticated,
                user: User(id: userId, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01'),
              ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('initial_sync_');
    Hive.init(tempDir.path);
    settings = await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer container(String? userId) {
    final c = ProviderContainer(overrides: [
      settingsBoxProvider.overrideWithValue(settings),
      authProvider.overrideWith((ref) => _FakeAuth(userId)),
      remoteReplicaDataSourceProvider.overrideWithValue(_EmptyRemote()),
      localDataSourceProvider.overrideWithValue(_EmptyLocal()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('a completed initial sync is remembered per user across launches', () async {
    final firstLaunch = container('user-a');
    expect(firstLaunch.read(initialSyncCompletedProvider), isFalse);

    expect(await firstLaunch.read(syncProgressProvider.notifier).startInitialSync('user-a'), isTrue);
    expect(firstLaunch.read(initialSyncCompletedProvider), isTrue);

    // A new launch (new container) does not block on the full replication again.
    expect(container('user-a').read(initialSyncCompletedProvider), isTrue);
    // Another account on the same device still gets its initial sync.
    expect(container('user-b').read(initialSyncCompletedProvider), isFalse);
    expect(container(null).read(initialSyncCompletedProvider), isFalse);
  });

  test('continuing offline is not recorded as a completed sync', () {
    final c = container('user-a');
    c.read(syncProgressProvider.notifier).continueOffline();

    expect(c.read(initialSyncCompletedProvider), isTrue);
    expect(isInitialSyncRecorded(settings, 'user-a'), isFalse);
  });

  test('isolation mode stops replication before any remote request', () async {
    await settings.put(NetworkPolicy.isolationModeKey, true);
    final remote = _CountingRemote();
    final c = ProviderContainer(overrides: [
      settingsBoxProvider.overrideWithValue(settings),
      authProvider.overrideWith((ref) => _FakeAuth('user-a')),
      remoteReplicaDataSourceProvider.overrideWithValue(remote),
      localDataSourceProvider.overrideWithValue(_EmptyLocal()),
    ]);
    addTearDown(c.dispose);

    expect(await c.read(syncProgressProvider.notifier).startInitialSync('user-a'), isFalse);
    expect(remote.calls, 0);
    expect(c.read(syncProgressProvider).canContinueOffline, isTrue);
    expect(isInitialSyncRecorded(settings, 'user-a'), isFalse);
  });

  test('replica fetch errors propagate instead of reading as empty tables', () async {
    final remote = RemoteReplicaDataSourceImpl(offlineSupabaseClient);

    await expectLater(remote.fetchReceipts('user-a'), throwsA(anything));
    await expectLater(remote.fetchBoxes('user-a'), throwsA(anything));
    await expectLater(remote.fetchAssets('user-a'), throwsA(anything));
    await expectLater(remote.fetchInvoices('user-a'), throwsA(anything));
  });
}
