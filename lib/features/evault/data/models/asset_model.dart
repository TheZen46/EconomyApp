import 'package:hive/hive.dart';

part 'asset_model.g.dart';

@HiveType(typeId: 7)
class AssetModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final DateTime purchaseDate;

  @HiveField(3)
  final int warrantyMonths;

  @HiveField(4)
  final double price;

  @HiveField(5)
  final String receiptImagePath;

  @HiveField(6)
  final String merchantName;
  
  @HiveField(7)
  final String? receiptId; // Link back to original receipt

  AssetModel({
    required this.id,
    required this.name,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.price,
    required this.receiptImagePath,
    required this.merchantName,
    this.receiptId,
  });

  DateTime get warrantyExpiryDate =>
      DateTime(purchaseDate.year, purchaseDate.month + warrantyMonths, purchaseDate.day, purchaseDate.hour, purchaseDate.minute);
  
  bool get isWarrantyActive => DateTime.now().isBefore(warrantyExpiryDate);
}
