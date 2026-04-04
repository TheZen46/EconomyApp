// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppConfigImpl _$$AppConfigImplFromJson(Map<String, dynamic> json) =>
    _$AppConfigImpl(
      key: json['key'] as String,
      value: json['value'] as String,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$$AppConfigImplToJson(_$AppConfigImpl instance) =>
    <String, dynamic>{
      'key': instance.key,
      'value': instance.value,
      'metadata': instance.metadata,
    };

_$ModelMetadataImpl _$$ModelMetadataImplFromJson(Map<String, dynamic> json) =>
    _$ModelMetadataImpl(
      downloadUrl: json['download_url'] as String,
      sizeMb: (json['size_mb'] as num).toDouble(),
      hash: json['hash'] as String?,
    );

Map<String, dynamic> _$$ModelMetadataImplToJson(_$ModelMetadataImpl instance) =>
    <String, dynamic>{
      'download_url': instance.downloadUrl,
      'size_mb': instance.sizeMb,
      'hash': instance.hash,
    };
