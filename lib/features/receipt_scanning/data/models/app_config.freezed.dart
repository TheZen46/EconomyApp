// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) {
  return _AppConfig.fromJson(json);
}

/// @nodoc
mixin _$AppConfig {
  String get key => throw _privateConstructorUsedError;
  String get value => throw _privateConstructorUsedError;
  Map<String, dynamic> get metadata => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AppConfigCopyWith<AppConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppConfigCopyWith<$Res> {
  factory $AppConfigCopyWith(AppConfig value, $Res Function(AppConfig) then) =
      _$AppConfigCopyWithImpl<$Res, AppConfig>;
  @useResult
  $Res call({String key, String value, Map<String, dynamic> metadata});
}

/// @nodoc
class _$AppConfigCopyWithImpl<$Res, $Val extends AppConfig>
    implements $AppConfigCopyWith<$Res> {
  _$AppConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? key = null,
    Object? value = null,
    Object? metadata = null,
  }) {
    return _then(_value.copyWith(
      key: null == key
          ? _value.key
          : key // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as String,
      metadata: null == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AppConfigImplCopyWith<$Res>
    implements $AppConfigCopyWith<$Res> {
  factory _$$AppConfigImplCopyWith(
          _$AppConfigImpl value, $Res Function(_$AppConfigImpl) then) =
      __$$AppConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String key, String value, Map<String, dynamic> metadata});
}

/// @nodoc
class __$$AppConfigImplCopyWithImpl<$Res>
    extends _$AppConfigCopyWithImpl<$Res, _$AppConfigImpl>
    implements _$$AppConfigImplCopyWith<$Res> {
  __$$AppConfigImplCopyWithImpl(
      _$AppConfigImpl _value, $Res Function(_$AppConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? key = null,
    Object? value = null,
    Object? metadata = null,
  }) {
    return _then(_$AppConfigImpl(
      key: null == key
          ? _value.key
          : key // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as String,
      metadata: null == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AppConfigImpl implements _AppConfig {
  const _$AppConfigImpl(
      {required this.key,
      required this.value,
      final Map<String, dynamic> metadata = const {}})
      : _metadata = metadata;

  factory _$AppConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppConfigImplFromJson(json);

  @override
  final String key;
  @override
  final String value;
  final Map<String, dynamic> _metadata;
  @override
  @JsonKey()
  Map<String, dynamic> get metadata {
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_metadata);
  }

  @override
  String toString() {
    return 'AppConfig(key: $key, value: $value, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppConfigImpl &&
            (identical(other.key, key) || other.key == key) &&
            (identical(other.value, value) || other.value == value) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, key, value, const DeepCollectionEquality().hash(_metadata));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AppConfigImplCopyWith<_$AppConfigImpl> get copyWith =>
      __$$AppConfigImplCopyWithImpl<_$AppConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppConfigImplToJson(
      this,
    );
  }
}

abstract class _AppConfig implements AppConfig {
  const factory _AppConfig(
      {required final String key,
      required final String value,
      final Map<String, dynamic> metadata}) = _$AppConfigImpl;

  factory _AppConfig.fromJson(Map<String, dynamic> json) =
      _$AppConfigImpl.fromJson;

  @override
  String get key;
  @override
  String get value;
  @override
  Map<String, dynamic> get metadata;
  @override
  @JsonKey(ignore: true)
  _$$AppConfigImplCopyWith<_$AppConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ModelMetadata _$ModelMetadataFromJson(Map<String, dynamic> json) {
  return _ModelMetadata.fromJson(json);
}

/// @nodoc
mixin _$ModelMetadata {
  @JsonKey(name: 'download_url')
  String get downloadUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_mb')
  double get sizeMb => throw _privateConstructorUsedError;
  String? get hash => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ModelMetadataCopyWith<ModelMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ModelMetadataCopyWith<$Res> {
  factory $ModelMetadataCopyWith(
          ModelMetadata value, $Res Function(ModelMetadata) then) =
      _$ModelMetadataCopyWithImpl<$Res, ModelMetadata>;
  @useResult
  $Res call(
      {@JsonKey(name: 'download_url') String downloadUrl,
      @JsonKey(name: 'size_mb') double sizeMb,
      String? hash});
}

/// @nodoc
class _$ModelMetadataCopyWithImpl<$Res, $Val extends ModelMetadata>
    implements $ModelMetadataCopyWith<$Res> {
  _$ModelMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? downloadUrl = null,
    Object? sizeMb = null,
    Object? hash = freezed,
  }) {
    return _then(_value.copyWith(
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      sizeMb: null == sizeMb
          ? _value.sizeMb
          : sizeMb // ignore: cast_nullable_to_non_nullable
              as double,
      hash: freezed == hash
          ? _value.hash
          : hash // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ModelMetadataImplCopyWith<$Res>
    implements $ModelMetadataCopyWith<$Res> {
  factory _$$ModelMetadataImplCopyWith(
          _$ModelMetadataImpl value, $Res Function(_$ModelMetadataImpl) then) =
      __$$ModelMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'download_url') String downloadUrl,
      @JsonKey(name: 'size_mb') double sizeMb,
      String? hash});
}

/// @nodoc
class __$$ModelMetadataImplCopyWithImpl<$Res>
    extends _$ModelMetadataCopyWithImpl<$Res, _$ModelMetadataImpl>
    implements _$$ModelMetadataImplCopyWith<$Res> {
  __$$ModelMetadataImplCopyWithImpl(
      _$ModelMetadataImpl _value, $Res Function(_$ModelMetadataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? downloadUrl = null,
    Object? sizeMb = null,
    Object? hash = freezed,
  }) {
    return _then(_$ModelMetadataImpl(
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      sizeMb: null == sizeMb
          ? _value.sizeMb
          : sizeMb // ignore: cast_nullable_to_non_nullable
              as double,
      hash: freezed == hash
          ? _value.hash
          : hash // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ModelMetadataImpl implements _ModelMetadata {
  const _$ModelMetadataImpl(
      {@JsonKey(name: 'download_url') required this.downloadUrl,
      @JsonKey(name: 'size_mb') required this.sizeMb,
      this.hash});

  factory _$ModelMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ModelMetadataImplFromJson(json);

  @override
  @JsonKey(name: 'download_url')
  final String downloadUrl;
  @override
  @JsonKey(name: 'size_mb')
  final double sizeMb;
  @override
  final String? hash;

  @override
  String toString() {
    return 'ModelMetadata(downloadUrl: $downloadUrl, sizeMb: $sizeMb, hash: $hash)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ModelMetadataImpl &&
            (identical(other.downloadUrl, downloadUrl) ||
                other.downloadUrl == downloadUrl) &&
            (identical(other.sizeMb, sizeMb) || other.sizeMb == sizeMb) &&
            (identical(other.hash, hash) || other.hash == hash));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, downloadUrl, sizeMb, hash);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ModelMetadataImplCopyWith<_$ModelMetadataImpl> get copyWith =>
      __$$ModelMetadataImplCopyWithImpl<_$ModelMetadataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ModelMetadataImplToJson(
      this,
    );
  }
}

abstract class _ModelMetadata implements ModelMetadata {
  const factory _ModelMetadata(
      {@JsonKey(name: 'download_url') required final String downloadUrl,
      @JsonKey(name: 'size_mb') required final double sizeMb,
      final String? hash}) = _$ModelMetadataImpl;

  factory _ModelMetadata.fromJson(Map<String, dynamic> json) =
      _$ModelMetadataImpl.fromJson;

  @override
  @JsonKey(name: 'download_url')
  String get downloadUrl;
  @override
  @JsonKey(name: 'size_mb')
  double get sizeMb;
  @override
  String? get hash;
  @override
  @JsonKey(ignore: true)
  _$$ModelMetadataImplCopyWith<_$ModelMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
