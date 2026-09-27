import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/sync_outbox_item.dart';
import 'outbox_service.dart';
import 'sync_manager.dart';
import '../../features/receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';
import '../../features/boxes/data/providers/boxes_provider.dart';
import '../../features/boxes/data/models/box_model.dart';
import '../../features/invoices/data/providers/invoices_provider.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/evault/presentation/providers/asset_provider.dart';
import '../../features/evault/data/models/asset_model.dart';

final outboxHiveBoxProvider = Provider<Box<SyncOutboxItem>>((ref) {
  throw UnimplementedError('Outbox Hive box must be overridden in main');
});

final outboxServiceProvider = Provider<OutboxService>((ref) {
  final box = ref.watch(outboxHiveBoxProvider);
  return OutboxService(box);
});

final syncManagerProvider = Provider<SyncManager?>((ref) {
  SupabaseClient client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    return null;
  }

  OutboxService outbox;
  try {
    outbox = ref.watch(outboxServiceProvider);
  } catch (_) {
    return null;
  }

  Box<ReceiptModel>? receipts;
  try {
    receipts = ref.watch(hiveBoxProvider);
  } catch (_) {}

  Box<BoxModel>? boxes;
  try {
    boxes = ref.watch(boxesHiveBoxProvider);
  } catch (_) {}

  Box<InvoiceModel>? invoices;
  try {
    invoices = ref.watch(invoicesHiveBoxProvider);
  } catch (_) {}

  Box<AssetModel>? assets;
  try {
    assets = ref.watch(assetsBoxProvider);
  } catch (_) {}

  Box? settings;
  try {
    settings = ref.watch(settingsBoxProvider);
  } catch (_) {}

  if (receipts == null || boxes == null || invoices == null || assets == null || settings == null) {
    return null;
  }

  return SyncManager(
    supabase: client,
    outboxService: outbox,
    receiptsBox: receipts,
    boxesBox: boxes,
    invoicesBox: invoices,
    assetsBox: assets,
    settingsBox: settings,
    onSyncCompleted: () {
      try {
        ref.read(receiptListProvider.notifier).loadReceipts();
      } catch (_) {}
      try {
        ref.read(boxesProvider.notifier).reload();
      } catch (_) {}
      try {
        ref.read(invoicesProvider.notifier).reload();
      } catch (_) {}
      try {
        ref.read(assetListProvider.notifier).reload();
      } catch (_) {}
    },
  );
});
