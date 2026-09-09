import 'hlc.dart';
import 'lww_register.dart';
import '../../features/receipt_scanning/data/models/receipt_model.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

/// CRDT representation of a receipt line item with field-level LWW registers.
class LineItemCrdt {
  final String id;
  final LwwRegister<String> description;
  final LwwRegister<int> unitPriceCents;
  final LwwRegister<int> quantity;
  final LwwRegister<String> category;
  final LwwRegister<String> necessity;
  final LwwRegister<int> taxRateBps;
  final LwwRegister<bool> isDeleted; // Tombstone flag

  const LineItemCrdt({
    required this.id,
    required this.description,
    required this.unitPriceCents,
    required this.quantity,
    required this.category,
    required this.necessity,
    required this.taxRateBps,
    required this.isDeleted,
  });

  /// Factory from standard model.
  factory LineItemCrdt.fromModel(
    ReceiptItemModel model,
    String itemId,
    Hlc hlc,
  ) {
    final int cents = (model.unitPrice * 100).round();
    return LineItemCrdt(
      id: itemId,
      description: LwwRegister(model.description, hlc),
      unitPriceCents: LwwRegister(cents, hlc),
      quantity: LwwRegister(model.quantity, hlc),
      category: LwwRegister(model.category ?? 'General', hlc),
      necessity: LwwRegister(model.necessity ?? 'essential', hlc),
      taxRateBps: LwwRegister(2200, hlc),
      isDeleted: LwwRegister(false, hlc),
    );
  }

  /// Merges another replica of this line item using field-level LWW resolution.
  LineItemCrdt merge(LineItemCrdt other) {
    assert(id == other.id, 'Cannot merge LineItems with different IDs ($id != ${other.id})');
    return LineItemCrdt(
      id: id,
      description: description.merge(other.description),
      unitPriceCents: unitPriceCents.merge(other.unitPriceCents),
      quantity: quantity.merge(other.quantity),
      category: category.merge(other.category),
      necessity: necessity.merge(other.necessity),
      taxRateBps: taxRateBps.merge(other.taxRateBps),
      isDeleted: isDeleted.merge(other.isDeleted),
    );
  }

  ReceiptItemModel toModel() {
    return ReceiptItemModel(
      description: description.value,
      unitPrice: unitPriceCents.value / 100.0,
      quantity: quantity.value,
      totalPrice: (unitPriceCents.value * quantity.value) / 100.0,
      category: category.value,
      necessity: necessity.value,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description.toJson((v) => v),
        'unitPriceCents': unitPriceCents.toJson((v) => v),
        'quantity': quantity.toJson((v) => v),
        'category': category.toJson((v) => v),
        'necessity': necessity.toJson((v) => v),
        'taxRateBps': taxRateBps.toJson((v) => v),
        'isDeleted': isDeleted.toJson((v) => v),
      };

  factory LineItemCrdt.fromJson(Map<String, dynamic> json) => LineItemCrdt(
        id: json['id'] as String,
        description: LwwRegister.fromJson(json['description'], (v) => v as String),
        unitPriceCents: LwwRegister.fromJson(json['unitPriceCents'], (v) => v as int),
        quantity: LwwRegister.fromJson(json['quantity'], (v) => v as int),
        category: LwwRegister.fromJson(json['category'], (v) => v as String),
        necessity: LwwRegister.fromJson(json['necessity'], (v) => v as String),
        taxRateBps: LwwRegister.fromJson(json['taxRateBps'], (v) => v as int),
        isDeleted: LwwRegister.fromJson(json['isDeleted'], (v) => v as bool),
      );
}

/// Composite Receipt CRDT containing field-level LWW registers and an LWW-Element-Map of items.
class ReceiptCrdt {
  final String id;
  final LwwRegister<String> merchantName;
  final LwwRegister<int> totalAmountCents;
  final LwwRegister<String> currency;
  final LwwRegister<int> receiptDateMillis;
  final LwwRegister<String> vatNumber;
  final LwwRegister<String> merchantAddress;
  final LwwRegister<String> boxId;
  final LwwRegister<bool> isDeleted; // Receipt Tombstone
  final Map<String, LineItemCrdt> items;

  const ReceiptCrdt({
    required this.id,
    required this.merchantName,
    required this.totalAmountCents,
    required this.currency,
    required this.receiptDateMillis,
    required this.vatNumber,
    required this.merchantAddress,
    required this.boxId,
    required this.isDeleted,
    required this.items,
  });

  /// Factory from standard `ReceiptModel`.
  factory ReceiptCrdt.fromModel(ReceiptModel model, Hlc hlc) {
    final int totalCents = (model.totalAmount * 100).round();
    final itemsMap = <String, LineItemCrdt>{};

    for (int i = 0; i < model.items.length; i++) {
      final itemId = '${model.id}_item_$i';
      itemsMap[itemId] = LineItemCrdt.fromModel(model.items[i], itemId, hlc);
    }

    return ReceiptCrdt(
      id: model.id,
      merchantName: LwwRegister(model.merchantName, hlc),
      totalAmountCents: LwwRegister(totalCents, hlc),
      currency: LwwRegister(model.currency, hlc),
      receiptDateMillis: LwwRegister(model.date.millisecondsSinceEpoch, hlc),
      vatNumber: LwwRegister(model.vatNumber, hlc),
      merchantAddress: LwwRegister(model.merchantAddress, hlc),
      boxId: LwwRegister(model.boxId ?? 'main', hlc),
      isDeleted: LwwRegister(model.deletedAt != null, hlc),
      items: itemsMap,
    );
  }

  /// Merges another replica of this receipt using state-based join-semilattice operator ($\sqcup$).
  ReceiptCrdt merge(ReceiptCrdt other) {
    assert(id == other.id, 'Cannot merge Receipts with different IDs ($id != ${other.id})');

    final mergedItems = Map<String, LineItemCrdt>.from(items);
    for (final entry in other.items.entries) {
      if (mergedItems.containsKey(entry.key)) {
        mergedItems[entry.key] = mergedItems[entry.key]!.merge(entry.value);
      } else {
        mergedItems[entry.key] = entry.value;
      }
    }

    return ReceiptCrdt(
      id: id,
      merchantName: merchantName.merge(other.merchantName),
      totalAmountCents: totalAmountCents.merge(other.totalAmountCents),
      currency: currency.merge(other.currency),
      receiptDateMillis: receiptDateMillis.merge(other.receiptDateMillis),
      vatNumber: vatNumber.merge(other.vatNumber),
      merchantAddress: merchantAddress.merge(other.merchantAddress),
      boxId: boxId.merge(other.boxId),
      isDeleted: isDeleted.merge(other.isDeleted),
      items: mergedItems,
    );
  }

  /// Materializes active (non-tombstoned) state into standard domain Receipt.
  Receipt toEntity() {
    final activeItems = items.values
        .where((item) => !item.isDeleted.value)
        .map((item) => item.toModel().toEntity())
        .toList();

    return Receipt(
      id: id,
      merchantName: merchantName.value,
      date: DateTime.fromMillisecondsSinceEpoch(receiptDateMillis.value, isUtc: true),
      totalAmount: totalAmountCents.value / 100.0,
      currency: currency.value,
      items: activeItems,
      vatNumber: vatNumber.value,
      merchantAddress: merchantAddress.value,
      boxId: boxId.value,
    );
  }

  /// Materializes into standard `ReceiptModel`.
  ReceiptModel toModel() {
    final activeItems = items.values
        .where((item) => !item.isDeleted.value)
        .map((item) => item.toModel())
        .toList();

    return ReceiptModel(
      id: id,
      merchantName: merchantName.value,
      date: DateTime.fromMillisecondsSinceEpoch(receiptDateMillis.value, isUtc: true),
      totalAmount: totalAmountCents.value / 100.0,
      currency: currency.value,
      items: activeItems,
      vatNumber: vatNumber.value,
      merchantAddress: merchantAddress.value,
      boxId: boxId.value,
      deletedAt: isDeleted.value ? DateTime.now().toUtc() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchantName': merchantName.toJson((v) => v),
        'totalAmountCents': totalAmountCents.toJson((v) => v),
        'currency': currency.toJson((v) => v),
        'receiptDateMillis': receiptDateMillis.toJson((v) => v),
        'vatNumber': vatNumber.toJson((v) => v),
        'merchantAddress': merchantAddress.toJson((v) => v),
        'boxId': boxId.toJson((v) => v),
        'isDeleted': isDeleted.toJson((v) => v),
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory ReceiptCrdt.fromJson(Map<String, dynamic> json) => ReceiptCrdt(
        id: json['id'] as String,
        merchantName: LwwRegister.fromJson(json['merchantName'], (v) => v as String),
        totalAmountCents: LwwRegister.fromJson(json['totalAmountCents'], (v) => v as int),
        currency: LwwRegister.fromJson(json['currency'], (v) => v as String),
        receiptDateMillis: LwwRegister.fromJson(json['receiptDateMillis'], (v) => v as int),
        vatNumber: LwwRegister.fromJson(json['vatNumber'], (v) => v as String),
        merchantAddress: LwwRegister.fromJson(json['merchantAddress'], (v) => v as String),
        boxId: LwwRegister.fromJson(json['boxId'], (v) => v as String),
        isDeleted: LwwRegister.fromJson(json['isDeleted'], (v) => v as bool),
        items: (json['items'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, LineItemCrdt.fromJson(v as Map<String, dynamic>)),
        ),
      );
}
