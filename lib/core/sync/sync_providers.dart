import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/sync_outbox_item.dart';
import 'outbox_service.dart';
import 'sync_manager.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../features/boxes/data/providers/boxes_provider.dart';
import '../../features/invoices/data/providers/invoices_provider.dart';
import '../../features/evault/presentation/providers/asset_provider.dart';

final outboxHiveBoxProvider = Provider<Box<SyncOutboxItem>>((ref) {
  throw UnimplementedError('Outbox Hive box must be overridden in main');
});

final outboxServiceProvider = Provider<OutboxService>((ref) {
  final box = ref.watch(outboxHiveBoxProvider);
  return OutboxService(box);
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  final outbox = ref.watch(outboxServiceProvider);
  final receipts = ref.watch(hiveBoxProvider);
  final boxes = ref.watch(boxesHiveBoxProvider);
  final invoices = ref.watch(invoicesHiveBoxProvider);
  final assets = ref.watch(assetsBoxProvider);
  final settings = ref.watch(settingsBoxProvider);

  return SyncManager(
    supabase: Supabase.instance.client,
    outboxService: outbox,
    receiptsBox: receipts,
    boxesBox: boxes,
    invoicesBox: invoices,
    assetsBox: assets,
    settingsBox: settings,
  );
});
