import 'package:hive/hive.dart';
import '../../domain/entities/receipt.dart';

part 'receipt_model.g.dart';

@HiveType(typeId: 0)
class ReceiptModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String merchantName;

  @HiveField(2)
  final DateTime date;

  @HiveField(3)
  final double totalAmount;

  @HiveField(4)
  final String currency;

  @HiveField(5)
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
  final String? boxId;

  @HiveField(12)
  final String? userId;

  @HiveField(13)
  final DateTime? createdAt;

  @HiveField(14)
  final DateTime? updatedAt;

  @HiveField(15)
  final DateTime? deletedAt;

  @HiveField(16)
  final int version;

  ReceiptModel({
    required this.id,
    required this.merchantName,
    required this.date,
    required this.totalAmount,
    required this.currency,
    required this.items,
    this.imagePath,
    this.vatNumber = '',
    this.merchantAddress = '',
    this.time = '',
    this.boxId = 'main',
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  factory ReceiptModel.fromJson(Map<String, dynamic> json) {
    // 1. Flatten Merchant
    final merchant = json['merchant'] as Map<String, dynamic>? ?? {};
    final merchantName = (json['merchant_name'] as String?) ??
        (merchant['name'] as String?) ??
        'Unknown Merchant';
    final vatNumber = (json['vat_number'] as String?) ?? (merchant['vat_number'] as String?) ?? '';
    final address = (json['merchant_address'] as String?) ?? (merchant['address'] as String?) ?? '';

    // 2. Flatten Transaction
    final transaction = json['transaction'] as Map<String, dynamic>? ?? {};
    final dateStr = (json['scanned_date'] as String?) ??
        (json['date'] as String?) ??
        (transaction['date'] as String?) ??
        DateTime.now().toIso8601String();
    final timeStr = (json['transaction_time'] as String?) ?? (transaction['time'] as String?) ?? '00:00';
    final currency = (json['currency'] as String?) ?? (transaction['currency'] as String?) ?? 'USD';
    final totalAmount = (json['total_amount'] as num?)?.toDouble() ??
        (transaction['total_amount'] as num?)?.toDouble() ??
        0.0;
    final boxId = (json['box_id'] as String?) ?? 'main';

    final itemsList = (json['items'] as List<dynamic>?)
            ?.map((e) => ReceiptItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return ReceiptModel(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      merchantName: merchantName,
      date: DateTime.tryParse(dateStr) ?? DateTime.now(),
      totalAmount: totalAmount,
      currency: currency,
      items: itemsList,
      imagePath: json['image_path'] as String?,
      vatNumber: vatNumber,
      merchantAddress: address,
      time: timeStr,
      boxId: boxId,
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant_name': merchantName,
      'scanned_date': date.toUtc().toIso8601String(),
      'total_amount': totalAmount,
      'currency': currency,
      'items': items.map((e) => e.toJson()).toList(),
      'image_path': imagePath,
      'vat_number': vatNumber,
      'merchant_address': merchantAddress,
      'transaction_time': time,
      'box_id': boxId ?? 'main',
      'user_id': userId,
      'created_at': (createdAt ?? date).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'version': version,
    };
  }

  Receipt toEntity() {
    return Receipt(
      id: id,
      merchantName: merchantName,
      date: date,
      totalAmount: totalAmount,
      currency: currency,
      items: items.map((e) => e.toEntity()).toList(),
      imagePath: imagePath,
      vatNumber: vatNumber,
      merchantAddress: merchantAddress,
      time: time,
      boxId: boxId ?? 'main',
    );
  }

  factory ReceiptModel.fromEntity(Receipt receipt, {String? userId, int version = 1}) {
    return ReceiptModel(
      id: receipt.id,
      merchantName: receipt.merchantName,
      date: receipt.date,
      totalAmount: receipt.totalAmount,
      currency: receipt.currency,
      items: receipt.items.map((e) => ReceiptItemModel.fromEntity(e)).toList(),
      imagePath: receipt.imagePath,
      vatNumber: receipt.vatNumber,
      merchantAddress: receipt.merchantAddress,
      time: receipt.time,
      boxId: receipt.boxId ?? 'main',
      userId: userId,
      version: version,
    );
  }

  ReceiptModel copyWith({
    String? id,
    String? merchantName,
    DateTime? date,
    double? totalAmount,
    String? currency,
    List<ReceiptItemModel>? items,
    String? imagePath,
    String? vatNumber,
    String? merchantAddress,
    String? time,
    String? boxId,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) {
    return ReceiptModel(
      id: id ?? this.id,
      merchantName: merchantName ?? this.merchantName,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      items: items ?? this.items,
      imagePath: imagePath ?? this.imagePath,
      vatNumber: vatNumber ?? this.vatNumber,
      merchantAddress: merchantAddress ?? this.merchantAddress,
      time: time ?? this.time,
      boxId: boxId ?? this.boxId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
    );
  }
}

@HiveType(typeId: 1)
class ReceiptItemModel {
  @HiveField(0)
  final String description;

  @HiveField(1)
  final double unitPrice;

  @HiveField(2)
  final int quantity;

  @HiveField(3)
  final double? totalPrice;

  @HiveField(4)
  final String? category;
  
  @HiveField(5)
  final String? necessity;

  @HiveField(6)
  final String? mainCategory;

  @HiveField(7)
  final String? subCategory;

  @HiveField(8)
  final bool? isAsset;

  @HiveField(9)
  final String? boxId;

  @HiveField(10)
  final bool isUserCorrected;

  @HiveField(11)
  final double confidenceScore;

  @HiveField(12)
  final DateTime? deletedAt;

  @HiveField(13)
  final int version;

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
    this.isUserCorrected = false,
    this.confidenceScore = 1.0,
    this.deletedAt,
    this.version = 1,
  });

  factory ReceiptItemModel.fromJson(Map<String, dynamic> json) {
    return ReceiptItemModel(
      description: json['description'] as String? ?? 'Item',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      totalPrice: (json['total_price'] as num?)?.toDouble(),
      category: json['category'] as String?,
      necessity: json['necessity'] as String? ?? 'unknown',
      mainCategory: json['main_category'] as String?,
      subCategory: json['sub_category'] as String?,
      isAsset: json['is_asset'] as bool? ?? false,
      boxId: json['box_id'] as String? ?? 'main',
      isUserCorrected: json['is_user_corrected'] as bool? ?? false,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 1.0,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'unit_price': unitPrice,
      'quantity': quantity,
      'total_price': totalPrice ?? (unitPrice * quantity),
      'category': category,
      'necessity': necessity ?? 'unknown',
      'main_category': mainCategory,
      'sub_category': subCategory,
      'is_asset': isAsset ?? false,
      'box_id': boxId ?? 'main',
      'is_user_corrected': isUserCorrected,
      'confidence_score': confidenceScore,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'version': version,
    };
  }

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
