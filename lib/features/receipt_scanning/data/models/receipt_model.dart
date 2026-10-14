import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:t_aidy/core/entities/syncable_entity.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/core/financial/price_basis.dart';
import 'package:t_aidy/core/data_contracts/remote_dtos.dart';
import '../../domain/entities/receipt.dart';

part 'receipt_model_adapter.dart';

/// Stored by the hand-written [ReceiptModelAdapter] (typeId 0) in receipt_model_adapter.dart.
/// Intentionally not annotated with @HiveType: generating the adapter would drop the
/// compatibility handling for records written by earlier versions.
class ReceiptModel extends HiveObject implements SyncableEntity {
  @override
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

  @override
  @HiveField(12)
  final String? userId;

  @HiveField(13)
  final DateTime? createdAt;

  @override
  @HiveField(14)
  final DateTime? updatedAt;

  @override
  @HiveField(15)
  final DateTime? deletedAt;

  @override
  @HiveField(16)
  final int version;

  @HiveField(17)
  final PriceBasis priceBasis;

  @HiveField(18)
  final int totalAmountMinor;

  /// Converts internal minor units to an exact fixed-point [Money] instance.
  Money get totalMoney => Money.fromMinorUnits(totalAmountMinor, currency: currency);

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
    this.priceBasis = PriceBasis.gross,
    int? totalAmountMinor,
  }) : totalAmountMinor = totalAmountMinor ?? Money.fromDecimal(totalAmount, currency: currency).cents;

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
    final totalAmountMinor = (json['total_amount_minor'] as num?)?.toInt() ??
        (transaction['total_amount_minor'] as num?)?.toInt();
    final boxId = (json['box_id'] as String?) ?? 'main';

    final itemsList = (json['items'] as List<dynamic>?)
            ?.map((e) => ReceiptItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return ReceiptModel(
      id: json['id'] as String? ?? const Uuid().v4(),
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
      priceBasis: PriceBasis.fromString(json['price_basis'] as String?),
      totalAmountMinor: totalAmountMinor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant_name': merchantName,
      'date': date.toUtc().toIso8601String(),
      'scanned_date': date.toUtc().toIso8601String(),
      'total_amount': totalAmount,
      'total_amount_minor': totalAmountMinor,
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
      'price_basis': priceBasis.name,
    };
  }

  /// Columns of `public.receipts` (see `supabase/migrations/`).
  ///
  /// PostgREST rejects a request body that contains any key outside this set
  /// with `PGRST204`, so every payload sent to the table must be restricted to it.
  static const Set<String> remoteColumns = {
    'id',
    'user_id',
    'merchant_name',
    'total_amount',
    'currency',
    'scanned_date',
    'image_path',
    'vat_number',
    'merchant_address',
    'transaction_time',
    'box_id',
    'items',
    'is_synced',
    'version',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  /// Row representation for `public.receipts`.
  ///
  /// Strictly serializes to schema-contracted columns defined in [ReceiptRemoteDto].
  Map<String, dynamic> toRemoteJson() => ReceiptRemoteDto.fromModel(this).toRemoteJson();

  /// Returns a copy of [payload] restricted to [remoteColumns].
  ///
  /// Applied at push time as well, so that outbox items enqueued before the
  /// payload was restricted are still accepted by the server.
  static Map<String, dynamic> sanitizeRemotePayload(Map<String, dynamic> payload) {
    return RemoteSchemaSerializer.sanitizeForTable('receipts', payload);
  }

  bool get isUserCorrected => items.any((e) => e.isUserCorrected);

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
      priceBasis: priceBasis,
      isUserCorrected: isUserCorrected,
    );
  }

  factory ReceiptModel.fromMoney({
    required String id,
    required String merchantName,
    required DateTime date,
    required Money totalMoney,
    required List<ReceiptItemModel> items,
    String? imagePath,
    String vatNumber = '',
    String merchantAddress = '',
    String time = '',
    String? boxId = 'main',
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int version = 1,
    PriceBasis priceBasis = PriceBasis.gross,
  }) {
    return ReceiptModel(
      id: id,
      merchantName: merchantName,
      date: date,
      totalAmount: totalMoney.toDouble,
      currency: totalMoney.currency,
      items: items,
      imagePath: imagePath,
      vatNumber: vatNumber,
      merchantAddress: merchantAddress,
      time: time,
      boxId: boxId,
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
      priceBasis: priceBasis,
      totalAmountMinor: totalMoney.cents,
    );
  }

  factory ReceiptModel.fromEntity(Receipt receipt, {String? userId, int version = 1}) {
    return ReceiptModel(
      id: receipt.id,
      merchantName: receipt.merchantName,
      date: receipt.date,
      totalAmount: receipt.totalAmount,
      currency: receipt.currency,
      items: receipt.items.map((e) => ReceiptItemModel.fromEntity(e, currency: receipt.currency)).toList(),
      imagePath: receipt.imagePath,
      vatNumber: receipt.vatNumber,
      merchantAddress: receipt.merchantAddress,
      time: receipt.time,
      boxId: receipt.boxId ?? 'main',
      userId: userId,
      version: version,
      priceBasis: receipt.priceBasis,
      totalAmountMinor: receipt.totalMoney.cents,
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
    PriceBasis? priceBasis,
    int? totalAmountMinor,
  }) {
    final effectiveCurrency = currency ?? this.currency;
    return ReceiptModel(
      id: id ?? this.id,
      merchantName: merchantName ?? this.merchantName,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: effectiveCurrency,
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
      priceBasis: priceBasis ?? this.priceBasis,
      totalAmountMinor: totalAmountMinor ??
          (totalAmount != null
              ? Money.fromDecimal(totalAmount, currency: effectiveCurrency).cents
              : this.totalAmountMinor),
    );
  }
}

/// Stored by the hand-written [ReceiptItemModelAdapter] (typeId 1) in receipt_model_adapter.dart.
/// Intentionally not annotated with @HiveType: generating the adapter would drop the
/// compatibility handling for records written by earlier versions.
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

  @HiveField(14)
  final PriceBasis priceBasis;

  @HiveField(15)
  final String id;

  @HiveField(16)
  final int unitPriceMinor;

  @HiveField(17)
  final int? totalPriceMinor;

  /// Converts unit price to fixed-point [Money].
  Money unitPriceMoney([String currency = 'EUR']) =>
      Money.fromMinorUnits(unitPriceMinor, currency: currency);

  /// Converts line item total price to fixed-point [Money].
  Money totalPriceMoney([String currency = 'EUR']) =>
      Money.fromMinorUnits(totalPriceMinor ?? (unitPriceMinor * quantity), currency: currency);

  ReceiptItemModel({
    String? id,
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
    this.priceBasis = PriceBasis.gross,
    int? unitPriceMinor,
    int? totalPriceMinor,
    String currency = 'EUR',
  })  : id = (id != null && id.isNotEmpty) ? id : const Uuid().v4(),
        unitPriceMinor = unitPriceMinor ?? Money.fromDecimal(unitPrice, currency: currency).cents,
        totalPriceMinor = totalPriceMinor ??
            (totalPrice != null
                ? Money.fromDecimal(totalPrice, currency: currency).cents
                : Money.fromDecimal(unitPrice, currency: currency).multiplyInt(quantity).cents);

  factory ReceiptItemModel.fromJson(Map<String, dynamic> json) {
    final unitPrice = (json['unit_price'] as num?)?.toDouble() ?? 0.0;
    final totalPrice = (json['total_price'] as num?)?.toDouble();
    final unitPriceMinor = (json['unit_price_minor'] as num?)?.toInt();
    final totalPriceMinor = (json['total_price_minor'] as num?)?.toInt();

    return ReceiptItemModel(
      id: json['id'] as String?,
      description: json['description'] as String? ?? 'Item',
      unitPrice: unitPrice,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      totalPrice: totalPrice,
      category: json['category'] as String?,
      necessity: json['necessity'] as String? ?? 'unknown',
      mainCategory: json['main_category'] as String?,
      subCategory: json['sub_category'] as String?,
      isAsset: json['is_asset'] as bool? ?? false,
      boxId: json['box_id'] as String? ?? 'main',
      isUserCorrected: json['is_user_corrected'] as bool? ?? false,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 1.0,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString()) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
      priceBasis: PriceBasis.fromString(json['price_basis'] as String?),
      unitPriceMinor: unitPriceMinor,
      totalPriceMinor: totalPriceMinor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'unit_price': unitPrice,
      'unit_price_minor': unitPriceMinor,
      'quantity': quantity,
      'total_price': totalPrice ?? (unitPrice * quantity),
      'total_price_minor': totalPriceMinor ?? (unitPriceMinor * quantity),
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
      'price_basis': priceBasis.name,
    };
  }

  ReceiptItemModel copyWith({
    String? id,
    String? description,
    double? unitPrice,
    int? quantity,
    double? totalPrice,
    String? category,
    String? necessity,
    String? mainCategory,
    String? subCategory,
    bool? isAsset,
    String? boxId,
    bool? isUserCorrected,
    double? confidenceScore,
    DateTime? deletedAt,
    int? version,
    PriceBasis? priceBasis,
    int? unitPriceMinor,
    int? totalPriceMinor,
    String? currency,
  }) {
    final effectiveCurrency = currency ?? 'EUR';
    return ReceiptItemModel(
      id: id ?? this.id,
      description: description ?? this.description,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      totalPrice: totalPrice ?? this.totalPrice,
      category: category ?? this.category,
      necessity: necessity ?? this.necessity,
      mainCategory: mainCategory ?? this.mainCategory,
      subCategory: subCategory ?? this.subCategory,
      isAsset: isAsset ?? this.isAsset,
      boxId: boxId ?? this.boxId,
      isUserCorrected: isUserCorrected ?? this.isUserCorrected,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      priceBasis: priceBasis ?? this.priceBasis,
      unitPriceMinor: unitPriceMinor ??
          (unitPrice != null
              ? Money.fromDecimal(unitPrice, currency: effectiveCurrency).cents
              : this.unitPriceMinor),
      totalPriceMinor: totalPriceMinor ??
          (totalPrice != null
              ? Money.fromDecimal(totalPrice, currency: effectiveCurrency).cents
              : this.totalPriceMinor),
      currency: effectiveCurrency,
    );
  }

  ReceiptItem toEntity() {
    return ReceiptItem(
      id: id,
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
      priceBasis: priceBasis,
      isUserCorrected: isUserCorrected,
    );
  }
  
  static ItemNecessity _parseNecessity(String val) {
    try {
      return ItemNecessity.values.firstWhere((e) => e.name == val);
    } catch (_) {
      return ItemNecessity.unknown;
    }
  }
  
  factory ReceiptItemModel.fromEntity(ReceiptItem item, {String currency = 'EUR'}) => ReceiptItemModel(
    id: item.id.isNotEmpty ? item.id : const Uuid().v4(),
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
    priceBasis: item.priceBasis,
    isUserCorrected: item.isUserCorrected,
    unitPriceMinor: item.unitPriceMoney(currency).cents,
    totalPriceMinor: item.totalPriceMoney(currency).cents,
    currency: currency,
  );
}
