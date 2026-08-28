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

  @HiveField(8)
  final String? userId;

  @HiveField(9)
  final String documentPath;

  @HiveField(10)
  final DateTime? createdAt;

  @HiveField(11)
  final DateTime? updatedAt;

  @HiveField(12)
  final DateTime? deletedAt;

  @HiveField(13)
  final int version;

  AssetModel({
    required this.id,
    required this.name,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.price,
    required this.receiptImagePath,
    required this.merchantName,
    this.receiptId,
    this.userId,
    this.documentPath = '',
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  factory AssetModel.fromJson(Map<String, dynamic> json) {
    return AssetModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Protected Item',
      purchaseDate: json['purchase_date'] != null
          ? DateTime.tryParse(json['purchase_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      warrantyMonths: (json['warranty_months'] as num?)?.toInt() ?? 12,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      receiptImagePath: json['receipt_image_path'] as String? ?? '',
      merchantName: json['merchant_name'] as String? ?? '',
      receiptId: json['receipt_id'] as String?,
      userId: json['user_id'] as String?,
      documentPath: json['document_path'] as String? ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'purchase_date': purchaseDate.toUtc().toIso8601String(),
      'warranty_months': warrantyMonths,
      'price': price,
      'receipt_image_path': receiptImagePath,
      'merchant_name': merchantName,
      'receipt_id': receiptId,
      'user_id': userId,
      'document_path': documentPath,
      'created_at': (createdAt ?? purchaseDate).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'version': version,
    };
  }

  DateTime get warrantyExpiryDate =>
      DateTime(purchaseDate.year, purchaseDate.month + warrantyMonths, purchaseDate.day, purchaseDate.hour, purchaseDate.minute);
  
  bool get isWarrantyActive => DateTime.now().isBefore(warrantyExpiryDate);

  AssetModel copyWith({
    String? id,
    String? name,
    DateTime? purchaseDate,
    int? warrantyMonths,
    double? price,
    String? receiptImagePath,
    String? merchantName,
    String? receiptId,
    String? userId,
    String? documentPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) {
    return AssetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      price: price ?? this.price,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      merchantName: merchantName ?? this.merchantName,
      receiptId: receiptId ?? this.receiptId,
      userId: userId ?? this.userId,
      documentPath: documentPath ?? this.documentPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
    );
  }
}
