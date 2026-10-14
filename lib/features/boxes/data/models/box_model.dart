import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:t_aidy/core/entities/syncable_entity.dart';
import 'package:t_aidy/core/financial/money.dart';
import 'package:t_aidy/core/data_contracts/remote_dtos.dart';

part 'box_model_adapter.dart';

/// Stored by the hand-written [BoxModelAdapter] (typeId 10) in box_model_adapter.dart.
/// Intentionally not annotated with @HiveType: generating the adapter would drop the
/// compatibility handling for records written by earlier versions.
class BoxModel extends HiveObject implements SyncableEntity {
  @override
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double budget;

  @HiveField(3)
  double spent;

  @HiveField(4)
  String currency;

  @HiveField(5)
  int color; // stored as ARGB int

  @HiveField(6)
  String? icon;

  @HiveField(7)
  bool autoCategorize;

  @HiveField(8)
  String keywords;

  @HiveField(9)
  bool isPrivate;

  @override
  @HiveField(10)
  String? userId;

  @HiveField(11)
  DateTime? createdAt;

  @override
  @HiveField(12)
  DateTime? updatedAt;

  @override
  @HiveField(13)
  DateTime? deletedAt;

  @override
  @HiveField(14)
  int version;

  @HiveField(15)
  int budgetMinor;

  @HiveField(16)
  int spentMinor;

  /// Budget amount as fixed-point [Money].
  Money get budgetMoney => Money.fromMinorUnits(budgetMinor, currency: currency);

  /// Spent amount as fixed-point [Money].
  Money get spentMoney => Money.fromMinorUnits(spentMinor, currency: currency);

  /// Remaining envelope balance as fixed-point [Money].
  Money get remainingMoney => budgetMoney - spentMoney;

  void setSpentMoney(Money money) {
    spent = money.toDouble;
    spentMinor = money.cents;
  }

  void setBudgetMoney(Money money) {
    budget = money.toDouble;
    budgetMinor = money.cents;
  }

  BoxModel({
    required this.id,
    required this.name,
    required this.budget,
    required this.spent,
    required this.currency,
    required this.color,
    this.icon,
    this.autoCategorize = false,
    this.keywords = '',
    this.isPrivate = false,
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.version = 1,
    int? budgetMinor,
    int? spentMinor,
  })  : budgetMinor = budgetMinor ?? Money.fromDecimal(budget, currency: currency).cents,
        spentMinor = spentMinor ?? Money.fromDecimal(spent, currency: currency).cents;

  factory BoxModel.fromJson(Map<String, dynamic> json) {
    final colorVal = json['color_hex'] ?? json['color'];
    final iconVal = json['icon_identifier'] ?? json['icon'];
    final budget = (json['budget'] as num?)?.toDouble() ?? 0.0;
    final spent = (json['spent'] as num?)?.toDouble() ?? 0.0;
    final currency = json['currency'] as String? ?? 'USD';
    final budgetMinor = (json['budget_minor'] as num?)?.toInt();
    final spentMinor = (json['spent_minor'] as num?)?.toInt();

    return BoxModel(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'Untitled Box',
      budget: budget,
      spent: spent,
      currency: currency,
      color: (colorVal as num?)?.toInt() ?? 0xFF002FA7,
      icon: iconVal as String?,
      autoCategorize: json['auto_categorize'] as bool? ?? false,
      keywords: json['keywords'] as String? ?? '',
      isPrivate: json['is_private'] as bool? ?? false,
      userId: json['user_id']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString()) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
      budgetMinor: budgetMinor,
      spentMinor: spentMinor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'budget': budget,
      'budget_minor': budgetMinor,
      'spent': spent,
      'spent_minor': spentMinor,
      'currency': currency,
      'color_hex': color,
      'icon_identifier': icon,
      'auto_categorize': autoCategorize,
      'keywords': keywords,
      'is_private': isPrivate,
      'user_id': userId,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'version': version,
    };
  }

  /// Strictly serializes to schema-contracted columns defined in [BoxRemoteDto].
  Map<String, dynamic> toRemoteJson() => BoxRemoteDto.fromModel(this).toRemoteJson();

  BoxModel copyWith({
    String? name,
    double? budget,
    double? spent,
    String? currency,
    int? color,
    String? icon,
    bool? autoCategorize,
    String? keywords,
    bool? isPrivate,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
    int? budgetMinor,
    int? spentMinor,
  }) {
    final effectiveCurrency = currency ?? this.currency;
    return BoxModel(
      id: id,
      name: name ?? this.name,
      budget: budget ?? this.budget,
      spent: spent ?? this.spent,
      currency: effectiveCurrency,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      autoCategorize: autoCategorize ?? this.autoCategorize,
      keywords: keywords ?? this.keywords,
      isPrivate: isPrivate ?? this.isPrivate,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      budgetMinor: budgetMinor ??
          (budget != null
              ? Money.fromDecimal(budget, currency: effectiveCurrency).cents
              : this.budgetMinor),
      spentMinor: spentMinor ??
          (spent != null
              ? Money.fromDecimal(spent, currency: effectiveCurrency).cents
              : this.spentMinor),
    );
  }
}
