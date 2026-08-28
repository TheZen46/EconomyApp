import 'package:hive/hive.dart';

part 'box_model.g.dart';

@HiveType(typeId: 10)
class BoxModel extends HiveObject {
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

  @HiveField(10)
  String? userId;

  @HiveField(11)
  DateTime? createdAt;

  @HiveField(12)
  DateTime? updatedAt;

  @HiveField(13)
  DateTime? deletedAt;

  @HiveField(14)
  int version;

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
  });

  factory BoxModel.fromJson(Map<String, dynamic> json) {
    return BoxModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Box',
      budget: (json['budget'] as num?)?.toDouble() ?? 0.0,
      spent: (json['spent'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      color: (json['color_hex'] as num?)?.toInt() ?? 0xFF002FA7,
      icon: json['icon_identifier'] as String?,
      autoCategorize: json['auto_categorize'] as bool? ?? false,
      keywords: json['keywords'] as String? ?? '',
      isPrivate: json['is_private'] as bool? ?? false,
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
      'name': name,
      'budget': budget,
      'spent': spent,
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
  }) {
    return BoxModel(
      id: id,
      name: name ?? this.name,
      budget: budget ?? this.budget,
      spent: spent ?? this.spent,
      currency: currency ?? this.currency,
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
    );
  }
}
