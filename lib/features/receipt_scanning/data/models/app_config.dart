import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_config.freezed.dart';
part 'app_config.g.dart';

@freezed
class AppConfig with _$AppConfig {
  const factory AppConfig({
    required String key,
    required String value,
    @Default({}) Map<String, dynamic> metadata,
  }) = _AppConfig;

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
}

@freezed
class ModelMetadata with _$ModelMetadata {
  const factory ModelMetadata({
    @JsonKey(name: 'download_url') required String downloadUrl,
    @JsonKey(name: 'size_mb') required double sizeMb,
    String? hash,
  }) = _ModelMetadata;

  factory ModelMetadata.fromJson(Map<String, dynamic> json) =>
      _$ModelMetadataFromJson(json);
}
