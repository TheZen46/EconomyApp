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

  UpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    double? progress,
    String? message,
    String? error,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

class ModelUpdateService extends StateNotifier<UpdateState> {
  final ModelRepository _repository;
  final Dio _dio;
  
  static const String _prefKeyLocalVersion = 'local_model_version';
  static const String _defaultVersion = '1.0.0';

  ModelUpdateService(this._repository) : _dio = Dio(), super(const UpdateState());

  Future<void> checkForUpdates() async {
    state = state.copyWith(isChecking: true, message: 'Checking for AI updates...');

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
            await _downloadModel(config.metadata['download_url'], remoteVersion);
          } else {
            state = state.copyWith(isChecking: false, message: null);
          }
        },
      );
    } catch (e) {
      state = state.copyWith(isChecking: false, error: e.toString());
    }
  }

  Future<void> _downloadModel(String? url, String version) async {
    if (url == null || url.isEmpty) {
      state = state.copyWith(isChecking: false, error: 'Invalid download URL');
      return;
    }

    state = state.copyWith(
      isChecking: false,
      isDownloading: true,
      message: 'Downloading AI Brain v$version...',
      progress: 0.0
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final savePath = '${modelsDir.path}/qwen2_vl_v$version.gguf';
      
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(progress: received / total);
          }
        },
      );

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
