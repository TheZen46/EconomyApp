// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'receipt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$Receipt {
  String get id => throw _privateConstructorUsedError;
  String get merchantName => throw _privateConstructorUsedError;
  String get vatNumber => throw _privateConstructorUsedError;
  String get merchantAddress => throw _privateConstructorUsedError;
  DateTime get date => throw _privateConstructorUsedError;
  String get time => throw _privateConstructorUsedError;
  double get totalAmount => throw _privateConstructorUsedError;
  String get currency =>
      throw _privateConstructorUsedError; // required String category, // Removed as per user request
  List<ReceiptItem> get items => throw _privateConstructorUsedError;
  String? get imagePath => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ReceiptCopyWith<Receipt> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ReceiptCopyWith<$Res> {
  factory $ReceiptCopyWith(Receipt value, $Res Function(Receipt) then) =
      _$ReceiptCopyWithImpl<$Res, Receipt>;
  @useResult
  $Res call(
      {String id,
      String merchantName,
      String vatNumber,
      String merchantAddress,
      DateTime date,
      String time,
      double totalAmount,
      String currency,
      List<ReceiptItem> items,
      String? imagePath});
}

/// @nodoc
class _$ReceiptCopyWithImpl<$Res, $Val extends Receipt>
    implements $ReceiptCopyWith<$Res> {
  _$ReceiptCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? merchantName = null,
    Object? vatNumber = null,
    Object? merchantAddress = null,
    Object? date = null,
    Object? time = null,
    Object? totalAmount = null,
    Object? currency = null,
    Object? items = null,
    Object? imagePath = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      merchantName: null == merchantName
          ? _value.merchantName
          : merchantName // ignore: cast_nullable_to_non_nullable
              as String,
      vatNumber: null == vatNumber
          ? _value.vatNumber
          : vatNumber // ignore: cast_nullable_to_non_nullable
              as String,
      merchantAddress: null == merchantAddress
          ? _value.merchantAddress
          : merchantAddress // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      time: null == time
          ? _value.time
          : time // ignore: cast_nullable_to_non_nullable
              as String,
      totalAmount: null == totalAmount
          ? _value.totalAmount
          : totalAmount // ignore: cast_nullable_to_non_nullable
              as double,
      currency: null == currency
          ? _value.currency
          : currency // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<ReceiptItem>,
      imagePath: freezed == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ReceiptImplCopyWith<$Res> implements $ReceiptCopyWith<$Res> {
  factory _$$ReceiptImplCopyWith(
          _$ReceiptImpl value, $Res Function(_$ReceiptImpl) then) =
      __$$ReceiptImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String merchantName,
      String vatNumber,
      String merchantAddress,
      DateTime date,
      String time,
      double totalAmount,
      String currency,
      List<ReceiptItem> items,
      String? imagePath});
}

/// @nodoc
class __$$ReceiptImplCopyWithImpl<$Res>
    extends _$ReceiptCopyWithImpl<$Res, _$ReceiptImpl>
    implements _$$ReceiptImplCopyWith<$Res> {
  __$$ReceiptImplCopyWithImpl(
      _$ReceiptImpl _value, $Res Function(_$ReceiptImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? merchantName = null,
    Object? vatNumber = null,
    Object? merchantAddress = null,
    Object? date = null,
    Object? time = null,
    Object? totalAmount = null,
    Object? currency = null,
    Object? items = null,
    Object? imagePath = freezed,
  }) {
    return _then(_$ReceiptImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      merchantName: null == merchantName
          ? _value.merchantName
          : merchantName // ignore: cast_nullable_to_non_nullable
              as String,
      vatNumber: null == vatNumber
          ? _value.vatNumber
          : vatNumber // ignore: cast_nullable_to_non_nullable
              as String,
      merchantAddress: null == merchantAddress
          ? _value.merchantAddress
          : merchantAddress // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      time: null == time
          ? _value.time
          : time // ignore: cast_nullable_to_non_nullable
              as String,
      totalAmount: null == totalAmount
          ? _value.totalAmount
          : totalAmount // ignore: cast_nullable_to_non_nullable
              as double,
      currency: null == currency
          ? _value.currency
          : currency // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<ReceiptItem>,
      imagePath: freezed == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$ReceiptImpl extends _Receipt {
  const _$ReceiptImpl(
      {required this.id,
      required this.merchantName,
      this.vatNumber = '',
      this.merchantAddress = '',
      required this.date,
      this.time = '',
      required this.totalAmount,
      required this.currency,
      final List<ReceiptItem> items = const [],
      this.imagePath})
      : _items = items,
        super._();

  @override
  final String id;
  @override
  final String merchantName;
  @override
  @JsonKey()
  final String vatNumber;
  @override
  @JsonKey()
  final String merchantAddress;
  @override
  final DateTime date;
  @override
  @JsonKey()
  final String time;
  @override
  final double totalAmount;
  @override
  final String currency;
// required String category, // Removed as per user request
  final List<ReceiptItem> _items;
// required String category, // Removed as per user request
  @override
  @JsonKey()
  List<ReceiptItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final String? imagePath;

  @override
  String toString() {
    return 'Receipt(id: $id, merchantName: $merchantName, vatNumber: $vatNumber, merchantAddress: $merchantAddress, date: $date, time: $time, totalAmount: $totalAmount, currency: $currency, items: $items, imagePath: $imagePath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReceiptImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.merchantName, merchantName) ||
                other.merchantName == merchantName) &&
            (identical(other.vatNumber, vatNumber) ||
                other.vatNumber == vatNumber) &&
            (identical(other.merchantAddress, merchantAddress) ||
                other.merchantAddress == merchantAddress) &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.time, time) || other.time == time) &&
            (identical(other.totalAmount, totalAmount) ||
                other.totalAmount == totalAmount) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.imagePath, imagePath) ||
                other.imagePath == imagePath));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      merchantName,
      vatNumber,
      merchantAddress,
      date,
      time,
      totalAmount,
      currency,
      const DeepCollectionEquality().hash(_items),
      imagePath);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReceiptImplCopyWith<_$ReceiptImpl> get copyWith =>
      __$$ReceiptImplCopyWithImpl<_$ReceiptImpl>(this, _$identity);
}

abstract class _Receipt extends Receipt {
  const factory _Receipt(
      {required final String id,
      required final String merchantName,
      final String vatNumber,
      final String merchantAddress,
      required final DateTime date,
      final String time,
      required final double totalAmount,
      required final String currency,
      final List<ReceiptItem> items,
      final String? imagePath}) = _$ReceiptImpl;
  const _Receipt._() : super._();

  @override
  String get id;
  @override
  String get merchantName;
  @override
  String get vatNumber;
  @override
  String get merchantAddress;
  @override
  DateTime get date;
  @override
  String get time;
  @override
  double get totalAmount;
  @override
  String get currency;
  @override // required String category, // Removed as per user request
  List<ReceiptItem> get items;
  @override
  String? get imagePath;
  @override
  @JsonKey(ignore: true)
  _$$ReceiptImplCopyWith<_$ReceiptImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ReceiptItem {
  String get description => throw _privateConstructorUsedError;
  double get unitPrice => throw _privateConstructorUsedError;
  int get quantity => throw _privateConstructorUsedError;
  double get totalPrice =>
      throw _privateConstructorUsedError; // New Taxonomy Fields
  ItemNecessity get necessity => throw _privateConstructorUsedError;
  String? get mainCategory =>
      throw _privateConstructorUsedError; // e.g. "Food & Drink"
  String? get subCategory =>
      throw _privateConstructorUsedError; // e.g. "Beverages (Sugary)"
  bool get isAsset => throw _privateConstructorUsedError;
  @Deprecated('Use subCategory or mainCategory instead')
  String? get category => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ReceiptItemCopyWith<ReceiptItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ReceiptItemCopyWith<$Res> {
  factory $ReceiptItemCopyWith(
          ReceiptItem value, $Res Function(ReceiptItem) then) =
      _$ReceiptItemCopyWithImpl<$Res, ReceiptItem>;
  @useResult
  $Res call(
      {String description,
      double unitPrice,
      int quantity,
      double totalPrice,
      ItemNecessity necessity,
      String? mainCategory,
      String? subCategory,
      bool isAsset,
      @Deprecated('Use subCategory or mainCategory instead') String? category});
}

/// @nodoc
class _$ReceiptItemCopyWithImpl<$Res, $Val extends ReceiptItem>
    implements $ReceiptItemCopyWith<$Res> {
  _$ReceiptItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? description = null,
    Object? unitPrice = null,
    Object? quantity = null,
    Object? totalPrice = null,
    Object? necessity = null,
    Object? mainCategory = freezed,
    Object? subCategory = freezed,
    Object? isAsset = null,
    Object? category = freezed,
  }) {
    return _then(_value.copyWith(
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      unitPrice: null == unitPrice
          ? _value.unitPrice
          : unitPrice // ignore: cast_nullable_to_non_nullable
              as double,
      quantity: null == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as int,
      totalPrice: null == totalPrice
          ? _value.totalPrice
          : totalPrice // ignore: cast_nullable_to_non_nullable
              as double,
      necessity: null == necessity
          ? _value.necessity
          : necessity // ignore: cast_nullable_to_non_nullable
              as ItemNecessity,
      mainCategory: freezed == mainCategory
          ? _value.mainCategory
          : mainCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      subCategory: freezed == subCategory
          ? _value.subCategory
          : subCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      isAsset: null == isAsset
          ? _value.isAsset
          : isAsset // ignore: cast_nullable_to_non_nullable
              as bool,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ReceiptItemImplCopyWith<$Res>
    implements $ReceiptItemCopyWith<$Res> {
  factory _$$ReceiptItemImplCopyWith(
          _$ReceiptItemImpl value, $Res Function(_$ReceiptItemImpl) then) =
      __$$ReceiptItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String description,
      double unitPrice,
      int quantity,
      double totalPrice,
      ItemNecessity necessity,
      String? mainCategory,
      String? subCategory,
      bool isAsset,
      @Deprecated('Use subCategory or mainCategory instead') String? category});
}

/// @nodoc
class __$$ReceiptItemImplCopyWithImpl<$Res>
    extends _$ReceiptItemCopyWithImpl<$Res, _$ReceiptItemImpl>
    implements _$$ReceiptItemImplCopyWith<$Res> {
  __$$ReceiptItemImplCopyWithImpl(
      _$ReceiptItemImpl _value, $Res Function(_$ReceiptItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? description = null,
    Object? unitPrice = null,
    Object? quantity = null,
    Object? totalPrice = null,
    Object? necessity = null,
    Object? mainCategory = freezed,
    Object? subCategory = freezed,
    Object? isAsset = null,
    Object? category = freezed,
  }) {
    return _then(_$ReceiptItemImpl(
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      unitPrice: null == unitPrice
          ? _value.unitPrice
          : unitPrice // ignore: cast_nullable_to_non_nullable
              as double,
      quantity: null == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as int,
      totalPrice: null == totalPrice
          ? _value.totalPrice
          : totalPrice // ignore: cast_nullable_to_non_nullable
              as double,
      necessity: null == necessity
          ? _value.necessity
          : necessity // ignore: cast_nullable_to_non_nullable
              as ItemNecessity,
      mainCategory: freezed == mainCategory
          ? _value.mainCategory
          : mainCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      subCategory: freezed == subCategory
          ? _value.subCategory
          : subCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      isAsset: null == isAsset
          ? _value.isAsset
          : isAsset // ignore: cast_nullable_to_non_nullable
              as bool,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$ReceiptItemImpl implements _ReceiptItem {
  const _$ReceiptItemImpl(
      {required this.description,
      required this.unitPrice,
      this.quantity = 1,
      required this.totalPrice,
      this.necessity = ItemNecessity.unknown,
      this.mainCategory,
      this.subCategory,
      this.isAsset = false,
      @Deprecated('Use subCategory or mainCategory instead') this.category});

  @override
  final String description;
  @override
  final double unitPrice;
  @override
  @JsonKey()
  final int quantity;
  @override
  final double totalPrice;
// New Taxonomy Fields
  @override
  @JsonKey()
  final ItemNecessity necessity;
  @override
  final String? mainCategory;
// e.g. "Food & Drink"
  @override
  final String? subCategory;
// e.g. "Beverages (Sugary)"
  @override
  @JsonKey()
  final bool isAsset;
  @override
  @Deprecated('Use subCategory or mainCategory instead')
  final String? category;

  @override
  String toString() {
    return 'ReceiptItem(description: $description, unitPrice: $unitPrice, quantity: $quantity, totalPrice: $totalPrice, necessity: $necessity, mainCategory: $mainCategory, subCategory: $subCategory, isAsset: $isAsset, category: $category)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReceiptItemImpl &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.unitPrice, unitPrice) ||
                other.unitPrice == unitPrice) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity) &&
            (identical(other.totalPrice, totalPrice) ||
                other.totalPrice == totalPrice) &&
            (identical(other.necessity, necessity) ||
                other.necessity == necessity) &&
            (identical(other.mainCategory, mainCategory) ||
                other.mainCategory == mainCategory) &&
            (identical(other.subCategory, subCategory) ||
                other.subCategory == subCategory) &&
            (identical(other.isAsset, isAsset) || other.isAsset == isAsset) &&
            (identical(other.category, category) ||
                other.category == category));
  }

  @override
  int get hashCode => Object.hash(runtimeType, description, unitPrice, quantity,
      totalPrice, necessity, mainCategory, subCategory, isAsset, category);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReceiptItemImplCopyWith<_$ReceiptItemImpl> get copyWith =>
      __$$ReceiptItemImplCopyWithImpl<_$ReceiptItemImpl>(this, _$identity);
}

abstract class _ReceiptItem implements ReceiptItem {
  const factory _ReceiptItem(
      {required final String description,
      required final double unitPrice,
      final int quantity,
      required final double totalPrice,
      final ItemNecessity necessity,
      final String? mainCategory,
      final String? subCategory,
      final bool isAsset,
      @Deprecated('Use subCategory or mainCategory instead')
      final String? category}) = _$ReceiptItemImpl;

  @override
  String get description;
  @override
  double get unitPrice;
  @override
  int get quantity;
  @override
  double get totalPrice;
  @override // New Taxonomy Fields
  ItemNecessity get necessity;
  @override
  String? get mainCategory;
  @override // e.g. "Food & Drink"
  String? get subCategory;
  @override // e.g. "Beverages (Sugary)"
  bool get isAsset;
  @override
  @Deprecated('Use subCategory or mainCategory instead')
  String? get category;
  @override
  @JsonKey(ignore: true)
  _$$ReceiptItemImplCopyWith<_$ReceiptItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
