import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../../core/privacy/network_policy.dart';
import '../../../../core/providers/supabase_providers.dart';
import '../../../boxes/data/models/box_model.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../evault/data/models/asset_model.dart';
import '../../../evault/presentation/providers/asset_provider.dart';
import '../../../invoices/data/models/invoice_model.dart';
import '../../../invoices/data/providers/invoices_provider.dart';
import '../../../receipt_scanning/data/datasources/sync_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../data/datasources/remote_replica_data_source.dart';
import '../../data/datasources/sync_engine.dart';
import '../../domain/entities/sync_progress_state.dart';

/// Provider for RemoteReplicaDataSource
final remoteReplicaDataSourceProvider = Provider<RemoteReplicaDataSource>((ref) {
  return RemoteReplicaDataSourceImpl(ref.watch(supabaseClientOrOfflineProvider));
});

/// Provider for the SyncEngine instance
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final remoteDataSource = ref.watch(remoteReplicaDataSourceProvider);
  final localDataSource = ref.watch(localDataSourceProvider);

  SyncService? uploadSyncService;
  try {
    uploadSyncService = ref.watch(syncServiceProvider);
  } catch (_) {}

  // Optional box access
  Box<AssetModel>? assetsBox;
  try {
    assetsBox = ref.watch(assetsBoxProvider);
  } catch (_) {}

  Box<BoxModel>? boxesBox;
  try {
    boxesBox = ref.watch(boxesHiveBoxProvider);
  } catch (_) {}

  Box<InvoiceModel>? invoicesBox;
  try {
    invoicesBox = ref.watch(invoicesHiveBoxProvider);
  } catch (_) {}

  final engine = SyncEngine(
    remoteDataSource: remoteDataSource,
    localDataSource: localDataSource,
    assetsBox: assetsBox,
    boxesBox: boxesBox,
    invoicesBox: invoicesBox,
    uploadSyncService: uploadSyncService,
    isCloudAllowed: () {
      try {
        return NetworkPolicy.isCloudAllowed(ref.read(settingsBoxProvider));
      } catch (_) {
        return true;
      }
    },
  );

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

/// Settings key listing the users whose initial synchronization has completed
/// on this device.
const String initialSyncUsersKey = 'initial_sync_completed_users';

/// Whether the initial synchronization of [userId] has completed on this device.
bool isInitialSyncRecorded(Box settingsBox, String userId) {
  final users = settingsBox.get(initialSyncUsersKey, defaultValue: const <dynamic>[]);
  return users is List && users.contains(userId);
}

/// Records that the initial synchronization of [userId] has completed.
Future<void> recordInitialSync(Box settingsBox, String userId) async {
  if (isInitialSyncRecorded(settingsBox, userId)) return;
  final users = settingsBox.get(initialSyncUsersKey, defaultValue: const <dynamic>[]);
  await settingsBox.put(initialSyncUsersKey, [if (users is List) ...users, userId]);
}

/// Tracks whether the initial post-login synchronization has concluded.
///
/// Starts from the completion recorded for the signed-in user, so that the
/// blocking full replication runs on the first sign-in on a device only;
/// later launches go straight to the app and synchronize in the background.
final initialSyncCompletedProvider = StateProvider<bool>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  if (userId == null) return false;
  try {
    return isInitialSyncRecorded(ref.watch(settingsBoxProvider), userId);
  } catch (_) {
    return false;
  }
});

/// State notifier managing UI progress state for synchronization.
class SyncProgressNotifier extends StateNotifier<SyncProgressState> {
  final SyncEngine _engine;
  final Ref _ref;
  StreamSubscription<SyncProgressState>? _engineSubscription;

  SyncProgressNotifier(this._engine, this._ref)
      : super(_engine.currentState) {
    _engineSubscription = _engine.stateStream.listen((state) {
      this.state = state;
      if (state.isCompleted) {
        _ref.read(initialSyncCompletedProvider.notifier).state = true;
        // Also refresh receiptListProvider so dashboard updates immediately
        try {
          _ref.invalidate(receiptListProvider);
        } catch (_) {}
      }
    });
  }

  /// Initiates initial replication upon successful user login.
  Future<bool> startInitialSync(String userId) async {
    _ref.read(initialSyncCompletedProvider.notifier).state = false;
    final success = await _engine.executeSync(userId: userId, isInitial: true);
    if (success) {
      await _recordCompletion(userId);
      _ref.read(initialSyncCompletedProvider.notifier).state = true;
    }
    return success;
  }

  /// Retries a failed or paused synchronization.
  Future<bool> retry(String userId) async {
    final success = await _engine.executeSync(userId: userId, isInitial: state.isInitialSync);
    if (success) await _recordCompletion(userId);
    return success;
  }

  /// Persists a completed replication. Continuing offline is not recorded,
  /// so the next launch offers the initial synchronization again.
  Future<void> _recordCompletion(String userId) async {
    try {
      await recordInitialSync(_ref.read(settingsBoxProvider), userId);
    } catch (e) {
      debugPrint('SyncProgressNotifier: could not record initial sync: $e');
    }
  }

  /// Continues into the application in offline mode.
  void continueOffline() {
    _engine.continueOffline();
    _ref.read(initialSyncCompletedProvider.notifier).state = true;
  }

  /// Manually triggers bidirectional synchronization anytime from settings.
  Future<bool> triggerBidirectionalSync(String userId) async {
    return await _engine.executeSync(userId: userId, isInitial: false);
  }

  @override
  void dispose() {
    _engineSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for UI consumption of sync progress and actions.
final syncProgressProvider =
    StateNotifierProvider<SyncProgressNotifier, SyncProgressState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return SyncProgressNotifier(engine, ref);
});
