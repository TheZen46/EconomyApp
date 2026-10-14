import 'package:uuid/uuid.dart';

import '../../features/boxes/data/models/box_model.dart';
import '../../features/evault/data/models/asset_model.dart';
import '../../features/invoices/data/models/invoice_model.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';

/// Centralized Data Transfer Objects (DTOs) enforcing single serialization contracts
/// between local Dart models and remote Supabase PostgreSQL schema tables.
///
/// PostgREST rejects any payload keys that do not strictly match table columns
/// with error code `PGRST204`. These DTOs guarantee schema conformity.

/// Remote DTO for `public.receipts`.
class ReceiptRemoteDto {
  final String id;
  final String? userId;
  final String merchantName;
  final double totalAmount;
  final String currency;
  final DateTime scannedDate;
  final String? imagePath;
  final String vatNumber;
  final String merchantAddress;
  final String transactionTime;
  final String boxId;
  final List<Map<String, dynamic>> items;
  final bool isSynced;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  static const Set<String> columns = {
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

  const ReceiptRemoteDto({
    required this.id,
    this.userId,
    this.merchantName = 'Unknown Merchant',
    this.totalAmount = 0.0,
    this.currency = 'USD',
    required this.scannedDate,
    this.imagePath,
    this.vatNumber = '',
    this.merchantAddress = '',
    this.transactionTime = '',
    this.boxId = 'main',
    this.items = const [],
    this.isSynced = true,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory ReceiptRemoteDto.fromRemoteJson(Map<String, dynamic> json) {
    final scannedDateStr = json['scanned_date'] as String? ??
        json['date'] as String? ??
        DateTime.now().toIso8601String();
    final itemsRaw = json['items'];
    final List<Map<String, dynamic>> itemsList;
    if (itemsRaw is List) {
      itemsList = itemsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      itemsList = const [];
    }

    return ReceiptRemoteDto(
      id: json['id'] as String? ?? const Uuid().v4(),
      userId: json['user_id'] as String?,
      merchantName: json['merchant_name'] as String? ?? 'Unknown Merchant',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      scannedDate: DateTime.tryParse(scannedDateStr) ?? DateTime.now(),
      imagePath: json['image_path'] as String?,
      vatNumber: json['vat_number'] as String? ?? '',
      merchantAddress: json['merchant_address'] as String? ?? '',
      transactionTime: json['transaction_time'] as String? ?? '',
      boxId: json['box_id'] as String? ?? 'main',
      items: itemsList,
      isSynced: json['is_synced'] as bool? ?? true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
    );
  }

  factory ReceiptRemoteDto.fromModel(ReceiptModel model, {String? userId}) {
    return ReceiptRemoteDto(
      id: model.id,
      userId: userId ?? model.userId,
      merchantName: model.merchantName,
      totalAmount: model.totalAmount,
      currency: model.currency,
      scannedDate: model.date,
      imagePath: model.imagePath,
      vatNumber: model.vatNumber,
      merchantAddress: model.merchantAddress,
      transactionTime: model.time,
      boxId: model.boxId ?? 'main',
      items: model.items.map((e) => e.toJson()).toList(),
      isSynced: true,
      version: model.version,
      createdAt: model.createdAt ?? model.date,
      updatedAt: model.updatedAt ?? DateTime.now(),
      deletedAt: model.deletedAt,
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      'merchant_name': merchantName,
      'total_amount': totalAmount,
      'currency': currency,
      'scanned_date': scannedDate.toUtc().toIso8601String(),
      'image_path': imagePath,
      'vat_number': vatNumber,
      'merchant_address': merchantAddress,
      'transaction_time': transactionTime,
      'box_id': boxId,
      'items': items,
      'is_synced': isSynced,
      'version': version,
      'created_at': (createdAt ?? scannedDate).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  ReceiptModel toModel() {
    final parsedItems = items.map((e) => ReceiptItemModel.fromJson(e)).toList();
    return ReceiptModel(
      id: id,
      merchantName: merchantName,
      date: scannedDate,
      totalAmount: totalAmount,
      currency: currency,
      items: parsedItems,
      imagePath: imagePath,
      vatNumber: vatNumber,
      merchantAddress: merchantAddress,
      time: transactionTime,
      boxId: boxId,
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
    );
  }
}

/// Remote DTO for `public.boxes`.
class BoxRemoteDto {
  final String id;
  final String? userId;
  final String name;
  final double budget;
  final double spent;
  final String currency;
  final int colorHex;
  final String? iconIdentifier;
  final bool autoCategorize;
  final String keywords;
  final bool isPrivate;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  static const Set<String> columns = {
    'id',
    'user_id',
    'name',
    'budget',
    'spent',
    'currency',
    'color_hex',
    'icon_identifier',
    'auto_categorize',
    'keywords',
    'is_private',
    'version',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  const BoxRemoteDto({
    required this.id,
    this.userId,
    this.name = 'Untitled Box',
    this.budget = 0.0,
    this.spent = 0.0,
    this.currency = 'USD',
    this.colorHex = 4278202791,
    this.iconIdentifier,
    this.autoCategorize = false,
    this.keywords = '',
    this.isPrivate = false,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory BoxRemoteDto.fromRemoteJson(Map<String, dynamic> json) {
    final colorVal = json['color_hex'] ?? json['color'];
    final iconVal = json['icon_identifier'] ?? json['icon'];

    return BoxRemoteDto(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userId: json['user_id']?.toString(),
      name: json['name'] as String? ?? 'Untitled Box',
      budget: (json['budget'] as num?)?.toDouble() ?? 0.0,
      spent: (json['spent'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      colorHex: (colorVal as num?)?.toInt() ?? 4278202791,
      iconIdentifier: iconVal as String?,
      autoCategorize: json['auto_categorize'] as bool? ?? false,
      keywords: json['keywords'] as String? ?? '',
      isPrivate: json['is_private'] as bool? ?? false,
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString()) : null,
    );
  }

  factory BoxRemoteDto.fromModel(BoxModel model, {String? userId}) {
    return BoxRemoteDto(
      id: model.id,
      userId: userId ?? model.userId,
      name: model.name,
      budget: model.budget,
      spent: model.spent,
      currency: model.currency,
      colorHex: model.color,
      iconIdentifier: model.icon,
      autoCategorize: model.autoCategorize,
      keywords: model.keywords,
      isPrivate: model.isPrivate,
      version: model.version,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt ?? DateTime.now(),
      deletedAt: model.deletedAt,
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      'name': name,
      'budget': budget,
      'spent': spent,
      'currency': currency,
      'color_hex': colorHex,
      'icon_identifier': iconIdentifier,
      'auto_categorize': autoCategorize,
      'keywords': keywords,
      'is_private': isPrivate,
      'version': version,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  BoxModel toModel() {
    return BoxModel(
      id: id,
      name: name,
      budget: budget,
      spent: spent,
      currency: currency,
      color: colorHex,
      icon: iconIdentifier,
      autoCategorize: autoCategorize,
      keywords: keywords,
      isPrivate: isPrivate,
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
    );
  }
}

/// Remote DTO for `public.invoices`.
class InvoiceRemoteDto {
  final String id;
  final String? userId;
  final String invoiceNumber;
  final String clientName;
  final double amount;
  final String currency;
  final String status;
  final DateTime issuedDate;
  final DateTime? dueDate;
  final String notes;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  static const Set<String> columns = {
    'id',
    'user_id',
    'invoice_number',
    'client_name',
    'amount',
    'currency',
    'status',
    'issued_date',
    'due_date',
    'notes',
    'version',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  const InvoiceRemoteDto({
    required this.id,
    this.userId,
    this.invoiceNumber = 'INV-001',
    this.clientName = 'Unknown Client',
    this.amount = 0.0,
    this.currency = 'USD',
    this.status = 'Draft',
    required this.issuedDate,
    this.dueDate,
    this.notes = '',
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory InvoiceRemoteDto.fromRemoteJson(Map<String, dynamic> json) {
    return InvoiceRemoteDto(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userId: json['user_id']?.toString(),
      invoiceNumber: json['invoice_number'] as String? ?? 'INV-001',
      clientName: json['client_name'] as String? ?? 'Unknown Client',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      status: json['status'] as String? ?? InvoiceStatus.draft,
      issuedDate: json['issued_date'] != null
          ? (DateTime.tryParse(json['issued_date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
      notes: json['notes'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString()) : null,
    );
  }

  factory InvoiceRemoteDto.fromModel(InvoiceModel model, {String? userId}) {
    return InvoiceRemoteDto(
      id: model.id,
      userId: userId ?? model.userId,
      invoiceNumber: model.invoiceNumber,
      clientName: model.clientName,
      amount: model.amount,
      currency: model.currency,
      status: model.status,
      issuedDate: model.issuedDate,
      dueDate: model.dueDate,
      notes: model.notes,
      version: model.version,
      createdAt: model.createdAt ?? model.issuedDate,
      updatedAt: model.updatedAt ?? DateTime.now(),
      deletedAt: model.deletedAt,
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      'invoice_number': invoiceNumber,
      'client_name': clientName,
      'amount': amount,
      'currency': currency,
      'status': status,
      'issued_date': issuedDate.toUtc().toIso8601String(),
      'due_date': dueDate?.toUtc().toIso8601String(),
      'notes': notes,
      'version': version,
      'created_at': (createdAt ?? issuedDate).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  InvoiceModel toModel() {
    return InvoiceModel(
      id: id,
      invoiceNumber: invoiceNumber,
      clientName: clientName,
      amount: amount,
      status: status,
      issuedDate: issuedDate,
      dueDate: dueDate,
      notes: notes,
      currency: currency,
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
    );
  }
}

/// Remote DTO for `public.vault_assets`.
class VaultAssetRemoteDto {
  final String id;
  final String? userId;
  final String? receiptId;
  final String name;
  final String merchantName;
  final DateTime purchaseDate;
  final int warrantyMonths;
  final double price;
  final String receiptImagePath;
  final String documentPath;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  static const Set<String> columns = {
    'id',
    'user_id',
    'receipt_id',
    'name',
    'merchant_name',
    'purchase_date',
    'warranty_months',
    'price',
    'receipt_image_path',
    'document_path',
    'version',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  const VaultAssetRemoteDto({
    required this.id,
    this.userId,
    this.receiptId,
    this.name = 'Protected Item',
    this.merchantName = '',
    required this.purchaseDate,
    this.warrantyMonths = 12,
    this.price = 0.0,
    this.receiptImagePath = '',
    this.documentPath = '',
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory VaultAssetRemoteDto.fromRemoteJson(Map<String, dynamic> json) {
    return VaultAssetRemoteDto(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userId: json['user_id']?.toString(),
      receiptId: json['receipt_id']?.toString(),
      name: json['name'] as String? ?? 'Protected Item',
      merchantName: json['merchant_name'] as String? ?? '',
      purchaseDate: json['purchase_date'] != null
          ? (DateTime.tryParse(json['purchase_date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      warrantyMonths: (json['warranty_months'] as num?)?.toInt() ?? 12,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      receiptImagePath: json['receipt_image_path'] as String? ?? '',
      documentPath: json['document_path'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString()) : null,
    );
  }

  factory VaultAssetRemoteDto.fromModel(AssetModel model, {String? userId}) {
    return VaultAssetRemoteDto(
      id: model.id,
      userId: userId ?? model.userId,
      receiptId: model.receiptId,
      name: model.name,
      merchantName: model.merchantName,
      purchaseDate: model.purchaseDate,
      warrantyMonths: model.warrantyMonths,
      price: model.price,
      receiptImagePath: model.receiptImagePath,
      documentPath: model.documentPath,
      version: model.version,
      createdAt: model.createdAt ?? model.purchaseDate,
      updatedAt: model.updatedAt ?? DateTime.now(),
      deletedAt: model.deletedAt,
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      'receipt_id': receiptId,
      'name': name,
      'merchant_name': merchantName,
      'purchase_date': purchaseDate.toUtc().toIso8601String(),
      'warranty_months': warrantyMonths,
      'price': price,
      'receipt_image_path': receiptImagePath,
      'document_path': documentPath,
      'version': version,
      'created_at': (createdAt ?? purchaseDate).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  AssetModel toModel() {
    return AssetModel(
      id: id,
      name: name,
      purchaseDate: purchaseDate,
      warrantyMonths: warrantyMonths,
      price: price,
      receiptImagePath: receiptImagePath,
      merchantName: merchantName,
      receiptId: receiptId,
      userId: userId,
      documentPath: documentPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
    );
  }
}

/// Central serialization dispatcher guaranteeing strict remote schema conformity.
class RemoteSchemaSerializer {
  RemoteSchemaSerializer._();

  static const Map<String, Set<String>> _tableColumns = {
    'receipts': ReceiptRemoteDto.columns,
    'boxes': BoxRemoteDto.columns,
    'invoices': InvoiceRemoteDto.columns,
    'vault_assets': VaultAssetRemoteDto.columns,
  };

  /// Validates and sanitizes [payload] for [table], stripping any uncontracted keys.
  static Map<String, dynamic> sanitizeForTable(String table, Map<String, dynamic> payload) {
    final validColumns = _tableColumns[table];
    if (validColumns == null) return payload;

    return {
      for (final entry in payload.entries)
        if (validColumns.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Whether [key] is a valid SQL column on [table].
  static bool isValidColumn(String table, String key) {
    return _tableColumns[table]?.contains(key) ?? false;
  }
}
