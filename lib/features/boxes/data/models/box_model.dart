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
  });

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
    );
  }
}
