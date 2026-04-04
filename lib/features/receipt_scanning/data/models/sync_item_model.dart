import 'package:hive/hive.dart';

part 'sync_item_model.g.dart';

@HiveType(typeId: 6)
class SyncItemModel {
  @HiveField(0)
  final String receiptId;

  @HiveField(1)
  final String imagePath;

  @HiveField(2)
  final DateTime addedAt;

  SyncItemModel({
    required this.receiptId,
    required this.imagePath,
    required this.addedAt,
  });
}
