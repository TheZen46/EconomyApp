// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
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
