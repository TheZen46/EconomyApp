import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/model_repository.dart';

// State to track download progress
class UpdateState {
  final bool isChecking;
  final bool isDownloading;
  final double progress;
  final String? message;
  final String? error;

  const UpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.progress = 0.0,
    this.message,
    this.error,
  });

  static const Object _keep = Object();

  /// Returns a copy with the given fields replaced. Passing `message: null` or
  /// `error: null` clears that field; omitting it keeps the current value.
  UpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    double? progress,
    Object? message = _keep,
    Object? error = _keep,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      message: identical(message, _keep) ? this.message : message as String?,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

/// A model update that passed [ModelUpdateService.validateUpdate].
class VerifiedModelUpdate {
  final String version;
  final Uri downloadUri;
  final String sha256;

  const VerifiedModelUpdate(this.version, this.downloadUri, this.sha256);
}

class ModelUpdateService extends StateNotifier<UpdateState> {
  final ModelRepository _repository;
  final Dio _dio;
  final Future<Directory> Function() _modelsDirectory;
  
  static const String _prefKeyLocalVersion = 'local_model_version';
  static const String _defaultVersion = '1.0.0';

  static final RegExp _versionPattern = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  ModelUpdateService(
    this._repository, {
    Dio? dio,
    Future<Directory> Function()? modelsDirectory,
    bool Function()? isCloudAllowed,
  })  : _dio = dio ?? Dio(),
        _modelsDirectory = modelsDirectory ?? _defaultModelsDirectory,
        _isCloudAllowed = isCloudAllowed ?? _alwaysAllowed,
        super(const UpdateState());

  /// Whether cloud requests are allowed (isolation mode is off).
  final bool Function() _isCloudAllowed;

  static bool _alwaysAllowed() => true;

  static Future<Directory> _defaultModelsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/models');
  }

  /// Checks a remote update description before anything is downloaded.
  ///
  /// The model file is executable input to the native engine, so an update is
  /// accepted only with a plain `X.Y.Z` version (it becomes part of the file
  /// name), an HTTPS download URL and the expected SHA-256 digest (metadata
  /// `hash`). Returns null when any of them is missing or malformed.
  static VerifiedModelUpdate? validateUpdate(String version, Map<String, dynamic> metadata) {
    if (!_versionPattern.hasMatch(version)) return null;
    final uri = Uri.tryParse(metadata['download_url'] as String? ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final hash = metadata['hash'] as String? ?? '';
    if (!_sha256Pattern.hasMatch(hash)) return null;
    return VerifiedModelUpdate(version, uri, hash.toLowerCase());
  }

  Future<void> checkForUpdates() async {
    // Isolation mode: no update check, no download.
    if (!_isCloudAllowed()) return;
    state = state.copyWith(isChecking: true, message: 'Checking for AI updates...', error: null);

    try {
      final configEither = await _repository.getLatestModelConfig();
      
      await configEither.fold(
        (failure) async {
          state = state.copyWith(isChecking: false, error: 'Failed to check updates');
        },
        (config) async {
          if (config == null) {
             state = state.copyWith(isChecking: false, message: null);
             return;
          }

          final prefs = await SharedPreferences.getInstance();
          final localVersion = prefs.getString(_prefKeyLocalVersion) ?? _defaultVersion;
          final remoteVersion = config.value;

          if (_isNewer(remoteVersion, localVersion)) {
            final update = validateUpdate(remoteVersion, config.metadata);
            if (update == null) {
              state = state.copyWith(
                isChecking: false,
                error: 'Model update rejected: missing or invalid version, HTTPS URL or SHA-256 digest',
              );
              return;
            }
            await _downloadModel(update);
          } else {
            state = state.copyWith(isChecking: false, message: null);
          }
        },
      );
    } catch (e) {
      state = state.copyWith(isChecking: false, error: e.toString());
    }
  }

  Future<void> _downloadModel(VerifiedModelUpdate update) async {
    final version = update.version;
    state = state.copyWith(
      isChecking: false,
      isDownloading: true,
      message: 'Downloading AI Brain v$version...',
      progress: 0.0
    );

    File? partFile;
    try {
      final modelsDir = await _modelsDirectory();
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final savePath = '${modelsDir.path}/qwen2_vl_v$version.gguf';
      partFile = File('$savePath.part');

      // Stage the download and install it only after its digest matches, so an
      // unverified file never appears under a name the engine may load.
      await _dio.download(
        update.downloadUri.toString(),
        partFile.path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(progress: received / total);
          }
        },
      );

      final actualSha256 = await _repository.calculateSha256(partFile);
      if (actualSha256.toLowerCase() != update.sha256) {
        await partFile.delete();
        state = state.copyWith(
          isDownloading: false,
          error: 'Model update failed integrity verification and was discarded',
        );
        return;
      }
      await partFile.rename(savePath);

      // Save new version
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLocalVersion, version);

      state = state.copyWith(
        isDownloading: false,
        message: 'AI Brain updated to v$version!',
        progress: 1.0,
      );
      
      // Clear message after delay
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
         state = state.copyWith(message: null);
      }

    } catch (e) {
      if (partFile != null && await partFile.exists()) {
        await partFile.delete();
      }
      state = state.copyWith(
        isDownloading: false,
        error: 'Download failed: $e',
      );
    }
  }

  bool _isNewer(String remote, String local) {
    // Simple semver compare (assumed format X.Y.Z)
    // For MVP, simple string comparison might suffice if formats are consistent,
    // but a robust split compare is safer.
    final rParts = remote.split('.').map(int.tryParse).toList();
    final lParts = local.split('.').map(int.tryParse).toList();
    
    for (var i = 0; i < 3; i++) {
      final r = (i < rParts.length) ? (rParts[i] ?? 0) : 0;
      final l = (i < lParts.length) ? (lParts[i] ?? 0) : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }
}
