// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
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
