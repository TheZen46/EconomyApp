import 'package:hive/hive.dart';

part 'user_profile_model.g.dart';

@HiveType(typeId: 13)
class UserProfileModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final double monthlyBudget;

  @HiveField(2)
  final String defaultCurrency;

  @HiveField(3)
  final String themeMode;

  @HiveField(4)
  final bool biometricEnabled;

  @HiveField(5)
  final bool googleDriveSyncEnabled;

  @HiveField(6)
  final int gamificationXp;

  @HiveField(7)
  final int gamificationStreak;

  @HiveField(8)
  final DateTime updatedAt;

  @HiveField(9)
  final int version;

  UserProfileModel({
    required this.id,
    this.monthlyBudget = 2000.0,
    this.defaultCurrency = 'USD',
    this.themeMode = 'system',
    this.biometricEnabled = false,
    this.googleDriveSyncEnabled = false,
    this.gamificationXp = 0,
    this.gamificationStreak = 0,
    DateTime? updatedAt,
    this.version = 1,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id'] as String? ?? '',
      monthlyBudget: (json['monthly_budget'] as num?)?.toDouble() ?? 2000.0,
      defaultCurrency: json['default_currency'] as String? ?? 'USD',
      themeMode: json['theme_mode'] as String? ?? 'system',
      biometricEnabled: json['biometric_enabled'] as bool? ?? false,
      googleDriveSyncEnabled: json['google_drive_sync_enabled'] as bool? ?? false,
      gamificationXp: (json['gamification_xp'] as num?)?.toInt() ?? 0,
      gamificationStreak: (json['gamification_streak'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now() : DateTime.now(),
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'monthly_budget': monthlyBudget,
      'default_currency': defaultCurrency,
      'theme_mode': themeMode,
      'biometric_enabled': biometricEnabled,
      'google_drive_sync_enabled': googleDriveSyncEnabled,
      'gamification_xp': gamificationXp,
      'gamification_streak': gamificationStreak,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version': version,
    };
  }

  UserProfileModel copyWith({
    String? id,
    double? monthlyBudget,
    String? defaultCurrency,
    String? themeMode,
    bool? biometricEnabled,
    bool? googleDriveSyncEnabled,
    int? gamificationXp,
    int? gamificationStreak,
    DateTime? updatedAt,
    int? version,
  }) {
    return UserProfileModel(
      id: id ?? this.id,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      themeMode: themeMode ?? this.themeMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      googleDriveSyncEnabled: googleDriveSyncEnabled ?? this.googleDriveSyncEnabled,
      gamificationXp: gamificationXp ?? this.gamificationXp,
      gamificationStreak: gamificationStreak ?? this.gamificationStreak,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }
}
