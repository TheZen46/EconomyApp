import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/receipt.dart';

part 'receipt_model.g.dart';

@HiveType(typeId: 0)
@JsonSerializable(explicitToJson: true)
class ReceiptModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  @JsonKey(name: 'merchant_name')
  final String merchantName;

  @HiveField(2)
  final DateTime date;

  @HiveField(3)
  @JsonKey(name: 'total_amount')
  final double totalAmount;

  @HiveField(4)
  final String currency;

  @HiveField(5)
  // @JsonKey(defaultValue: 'Uncategorized')
  // final String category; // Removed

  @HiveField(6)
  final List<ReceiptItemModel> items;

  @HiveField(7)
  final String? imagePath;

  @HiveField(8)
  final String vatNumber;

  @HiveField(9)
  final String merchantAddress;

  @HiveField(10)
  final String time;

  @HiveField(11)
  @JsonKey(name: 'box_id', defaultValue: 'main')
  final String? boxId;

  ReceiptModel({
    required this.id,
    required this.merchantName,
    required this.date,
    required this.totalAmount,
    required this.currency,
    // required this.category,
    required this.items,
    this.imagePath,
    this.vatNumber = '',
    this.merchantAddress = '',
    this.time = '',
    this.boxId = 'main',
  });

  // Custom fromJson to handle the "Perfect JSON" nested structure
  factory ReceiptModel.fromJson(Map<String, dynamic> json) {
    // 1. Flatten Merchant
    final merchant = json['merchant'] as Map<String, dynamic>? ?? {};
    final merchantName = merchant['name'] as String? ?? 'Unknown Merchant';
    final vatNumber = merchant['vat_number'] as String? ?? '';
    final address = merchant['address'] as String? ?? '';

    // 2. Flatten Transaction
    final transaction = json['transaction'] as Map<String, dynamic>? ?? {};
    final dateStr = transaction['date'] as String? ?? DateTime.now().toIso8601String();
    final timeStr = transaction['time'] as String? ?? '00:00';
    final currency = transaction['currency'] as String? ?? 'EUR';
    final totalAmount = (transaction['total_amount'] as num?)?.toDouble() ?? 0.0;
    final boxId = json['box_id'] as String? ?? 'main';
    
    // 3. Category & Items
    // final category = json['category'] as String? ?? 'Uncategorized';
    final itemsList = (json['items'] as List<dynamic>?)
        ?.map((e) => ReceiptItemModel.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return ReceiptModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Generate ID on import
      merchantName: merchantName,
      date: DateTime.tryParse(dateStr) ?? DateTime.now(),
      totalAmount: totalAmount,
      currency: currency,
      // category: category,
      items: itemsList,
      vatNumber: vatNumber,
      merchantAddress: address,
      time: timeStr,
      boxId: boxId,
    );
  }
  
  // Note: explicitToJson: true handles nested items, but for the "Perfect JSON" export 
  // we would need a custom toJson if we wanted to export back to that format. 
  // For Hive/Internal storage, standard flat JSON is fine. 
  // But wait, the generated code expects standard structure. 
  // I will disable the generated fromJson for the outer class to avoid conflicts 
  // or just use this manual one.
  // The @JsonSerializable annotation normally generates it. 
  // I'll leave toJson as generated (flat) but use my custom factory for import.

  Map<String, dynamic> toJson() => _$ReceiptModelToJson(this);

  Receipt toEntity() {
    return Receipt(
      id: id,
      merchantName: merchantName,
      date: date,
      totalAmount: totalAmount,
      currency: currency,
      // category: category,
      items: items.map((e) => e.toEntity()).toList(),
      imagePath: imagePath,
      vatNumber: vatNumber,
      merchantAddress: merchantAddress,
      time: time,
      boxId: boxId ?? 'main',
    );
  }

  factory ReceiptModel.fromEntity(Receipt receipt) {
    return ReceiptModel(
      id: receipt.id,
      merchantName: receipt.merchantName,
      date: receipt.date,
      totalAmount: receipt.totalAmount,
      currency: receipt.currency,
      // category: receipt.category, // Computed now
      items: receipt.items.map((e) => ReceiptItemModel.fromEntity(e)).toList(),
      imagePath: receipt.imagePath,
      vatNumber: receipt.vatNumber,
      merchantAddress: receipt.merchantAddress,
      time: receipt.time,
      boxId: receipt.boxId ?? 'main',
    );
  }
}

@HiveType(typeId: 1)
@JsonSerializable()
class ReceiptItemModel {
  @HiveField(0)
  @JsonKey(name: 'description')
  final String description;

  @HiveField(1)
  @JsonKey(name: 'unit_price')
  final double unitPrice;

  @HiveField(2)
  final int quantity;

  @HiveField(3)
  @JsonKey(name: 'total_price')
  final double? totalPrice;

  @HiveField(4)
  final String? category;
  
  @HiveField(5)
  @JsonKey(defaultValue: 'unknown')
  final String? necessity; // Nullable for schema migration

  @HiveField(6)
  @JsonKey(name: 'main_category')
  final String? mainCategory;

  @HiveField(7)
  @JsonKey(name: 'sub_category')
  final String? subCategory;

  @HiveField(8)
  @JsonKey(name: 'is_asset', defaultValue: false)
  final bool? isAsset; // Nullable for migration

  @HiveField(9)
  @JsonKey(name: 'box_id', defaultValue: 'main')
  final String? boxId;

  ReceiptItemModel({
    required this.description,
    required this.unitPrice,
    required this.quantity,
    this.totalPrice,
    this.category,
    this.necessity,
    this.mainCategory,
    this.subCategory,
    this.isAsset = false,
    this.boxId = 'main',
  });

  factory ReceiptItemModel.fromJson(Map<String, dynamic> json) => _$ReceiptItemModelFromJson(json);
  Map<String, dynamic> toJson() => _$ReceiptItemModelToJson(this);

  ReceiptItem toEntity() {
    return ReceiptItem(
      description: description, 
      unitPrice: unitPrice, 
      quantity: quantity,
      totalPrice: totalPrice ?? (unitPrice * quantity),
      category: category,
      necessity: _parseNecessity(necessity ?? 'unknown'),
      mainCategory: mainCategory,
      subCategory: subCategory,
      isAsset: isAsset ?? false,
      boxId: boxId ?? 'main',
    );
  }
  
  static ItemNecessity _parseNecessity(String val) {
    try {
      return ItemNecessity.values.firstWhere((e) => e.name == val);
    } catch (_) {
      return ItemNecessity.unknown;
    }
  }
  
  factory ReceiptItemModel.fromEntity(ReceiptItem item) => ReceiptItemModel(
    description: item.description,
    unitPrice: item.unitPrice,
    quantity: item.quantity,
    totalPrice: item.totalPrice,
    category: item.category,
    necessity: item.necessity.name,
    mainCategory: item.mainCategory,
    subCategory: item.subCategory,
    isAsset: item.isAsset,
    boxId: item.boxId ?? 'main',
  );
}
