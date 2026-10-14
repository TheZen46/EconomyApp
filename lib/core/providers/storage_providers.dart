import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../sync/models/sync_outbox_item.dart';
import '../../features/boxes/data/models/box_model.dart';
import '../../features/evault/data/models/asset_model.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';
import '../../features/receipt_scanning/data/models/sync_item_model.dart';

/// Shared Hive box storing user preferences and application configuration (`settings`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final settingsBoxProvider = Provider<Box>((ref) {
  throw UnimplementedError('Settings Hive box must be overridden in main');
});

/// Hive box storing persisted [ReceiptModel] records (`receipts_v3`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final receiptsBoxProvider = Provider<Box<ReceiptModel>>((ref) {
  throw UnimplementedError('Receipts Hive box must be overridden in main');
});

/// Alias for [receiptsBoxProvider] for backward compatibility.
final hiveBoxProvider = receiptsBoxProvider;

/// Hive box storing temporary upload jobs for attachments and training labels (`sync_queue`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final syncBoxProvider = Provider<Box<SyncItemModel>>((ref) {
  throw UnimplementedError('Sync queue Hive box must be overridden in main');
});

/// Hive box storing budget boxes (`boxes`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final boxesBoxProvider = Provider<Box<BoxModel>>((ref) {
  throw UnimplementedError('Boxes Hive box must be overridden in main');
});

/// Alias for [boxesBoxProvider] for backward compatibility.
final boxesHiveBoxProvider = boxesBoxProvider;

/// Hive box storing invoices (`invoices`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final invoicesBoxProvider = Provider<Box<InvoiceModel>>((ref) {
  throw UnimplementedError('Invoices Hive box must be overridden in main');
});

/// Alias for [invoicesBoxProvider] for backward compatibility.
final invoicesHiveBoxProvider = invoicesBoxProvider;

/// Hive box storing EVault asset inventory (`assets`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an encrypted box instance in `main()`.
/// **Dependencies:** None.
final assetsBoxProvider = Provider<Box<AssetModel>>((ref) {
  throw UnimplementedError('Assets Hive box must be overridden in main');
});

/// Hive box storing persistent outgoing [SyncOutboxItem] mutations (`sync_outbox`).
///
/// **Lifetime:** App-scoped singleton.
/// **Override:** Required. Must be overridden with an opened encrypted box in `main()`.
/// **Dependencies:** None.
final outboxHiveBoxProvider = Provider<Box<SyncOutboxItem>>((ref) {
  throw UnimplementedError('Outbox Hive box must be overridden in main');
});
