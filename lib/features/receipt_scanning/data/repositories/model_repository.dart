import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
import '../../../../core/error/failures.dart';
import '../models/app_config.dart';

/// Single source of truth for model metadata and endpoints.
class LocalModelInfo {
  final String id;
  final String name;
  final String fileName;
  final String sizeLabel;
  final String downloadUrl;
  final String expectedSha256;
  final String? mmprojFileName;
  final String? mmprojSizeLabel;
  final String? mmprojDownloadUrl;
  final String? mmprojExpectedSha256;
  final bool isMultimodal;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sizeLabel,
    required this.downloadUrl,
    required this.expectedSha256,
    this.mmprojFileName,
    this.mmprojSizeLabel,
    this.mmprojDownloadUrl,
    this.mmprojExpectedSha256,
    this.isMultimodal = false,
  });

  /// Multimodal vision projector companion artifact if this model requires one.
  LocalModelInfo? get mmprojInfo => (isMultimodal &&
          mmprojFileName != null &&
          mmprojDownloadUrl != null &&
          mmprojExpectedSha256 != null)
      ? LocalModelInfo(
          id: '$id-mmproj',
          name: '$name (Vision Projector)',
          fileName: mmprojFileName!,
          sizeLabel: mmprojSizeLabel ?? '',
          downloadUrl: mmprojDownloadUrl!,
          expectedSha256: mmprojExpectedSha256!,
          isMultimodal: false,
        )
      : null;

  /// Qwen2-VL-2B-Instruct multimodal receipt model & CLIP projector (4GB+ RAM devices)
  /// Upstream commit: 2160e265f926e84e84dbb1c73e623b5324b23707
  static const qwen2vl2b = LocalModelInfo(
    id: 'qwen2-vl-2b',
    name: 'Qwen2-VL 2B Multimodal (Standard)',
    fileName: 'qwen2_vl_2b.Q4_K_M.gguf',
    sizeLabel: '~986 MB (Requires 4GB+ RAM)',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/2160e265f926e84e84dbb1c73e623b5324b23707/Qwen2-VL-2B-Instruct-Q4_K_M.gguf?download=true',
    expectedSha256:
        '4ef095263343fc1237e8ca879790bb262bcf209f082e0a9bfce219b7ece55e8b',
    mmprojFileName: 'qwen2_vl_2b.mmproj.gguf',
    mmprojSizeLabel: '~1.33 GB (Vision Projector)',
    mmprojDownloadUrl:
        'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/2160e265f926e84e84dbb1c73e623b5324b23707/mmproj-Qwen2-VL-2B-Instruct-f16.gguf?download=true',
    mmprojExpectedSha256:
        '05cc3ae461a7b6aa4023312ccab549ecab77cf8677efee04f049fcbab55b8bc3',
    isMultimodal: true,
  );

  /// SmolVLM-Instruct multimodal model for low-memory devices (< 4GB RAM)
  /// Upstream commit: e75618fdae83145c487f1b4d8115bb02a5b58ecc
  static const smolVlm500m = LocalModelInfo(
    id: 'smolvlm-500m',
    name: 'SmolVLM 500M (Low-RAM Devices < 4GB)',
    fileName: 'smolvlm_500m.Q4_K_M.gguf',
    sizeLabel: '~1.11 GB (Optimized for <4GB RAM)',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM-Instruct-GGUF/resolve/e75618fdae83145c487f1b4d8115bb02a5b58ecc/SmolVLM-Instruct-Q4_K_M.gguf?download=true',
    expectedSha256:
        'dc80966bd84789de64115f07888939c03abb1714d431c477dfb405517a554af5',
    mmprojFileName: 'smolvlm_500m.mmproj.gguf',
    mmprojSizeLabel: '~872 MB (Vision Projector)',
    mmprojDownloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM-Instruct-GGUF/resolve/e75618fdae83145c487f1b4d8115bb02a5b58ecc/mmproj-SmolVLM-Instruct-f16.gguf?download=true',
    mmprojExpectedSha256:
        '670c0a23196cce1be845e704775c68a4f757e6aea6898314201b46529070bdb7',
    isMultimodal: true,
  );

  /// Legacy Gemma 2B IT model endpoint & expected SHA-256 checksum (text-only OCR fallback, not a VLM)
  static const gemma2b = LocalModelInfo(
    id: 'gemma-2b-it',
    name: 'Gemma 2B IT',
    fileName: 'gemma-2b-it.Q4_K_M.gguf',
    sizeLabel: '~1.47 GB (Legacy OCR Fallback)',
    downloadUrl:
        'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it.Q4_K_M.gguf?download=true',
    expectedSha256:
        'e29d72dfbf2e9bcba97fef2b860655bf965c71a3962d3e1dbf3ca3e50a7c490a',
    isMultimodal: false,
  );

  static const defaultModel = qwen2vl2b;

  /// Candidate models for Vision-Language multimodal receipt intelligence.
  /// Text-only models like Gemma are explicitly excluded.
  static const List<LocalModelInfo> vlmCandidates = [
    qwen2vl2b,
    smolVlm500m,
  ];

  /// All known model definitions.
  static const List<LocalModelInfo> allModels = [
    qwen2vl2b,
    smolVlm500m,
    gemma2b,
  ];
}

/// Helper to estimate available system physical RAM and recommend appropriate model tier.
class DeviceMemoryHelper {
  DeviceMemoryHelper._();

  /// Returns total physical RAM in Megabytes (MB).
  static Future<int> getTotalRamMB() async {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final meminfoFile = File('/proc/meminfo');
        if (await meminfoFile.exists()) {
          final lines = await meminfoFile.readAsLines();
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 2) {
                final totalKb = int.tryParse(parts[1]) ?? 0;
                return (totalKb / 1024).round();
              }
            }
          }
        }
      }
    } catch (_) {
      // Fallback
    }
    // Default estimate for desktop / standard devices
    return 6144;
  }

  /// Determines whether the device is in the low-RAM tier (< 4 GB).
  static Future<bool> isLowMemoryDevice() async {
    final ramMB = await getTotalRamMB();
    // Threshold set at 3900 MB to safely capture nominal 4GB devices
    return ramMB < 3900;
  }

  /// Returns recommended model based on device RAM constraints.
  static Future<LocalModelInfo> getRecommendedModel() async {
    final isLowRam = await isLowMemoryDevice();
    if (isLowRam) {
      return LocalModelInfo.smolVlm500m;
    }
    return LocalModelInfo.qwen2vl2b;
  }
}

abstract class ModelRepository {
  Future<Either<Failure, AppConfig?>> getLatestModelConfig();
  LocalModelInfo get defaultModelInfo => LocalModelInfo.defaultModel;
  Future<LocalModelInfo> getRecommendedModelInfo() => DeviceMemoryHelper.getRecommendedModel();

  /// Calculates the SHA-256 hex string for a file using streaming reads.
  Future<String> calculateSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Verifies if [modelFile] exists, is non-empty, and matches [expectedSha256].
  Future<bool> verifyModelIntegrity(File modelFile, String expectedSha256) async {
    if (!await modelFile.exists()) return false;
    final length = await modelFile.length();
    if (length == 0) return false;
    if (expectedSha256.isEmpty) return true;

    final actualHash = await calculateSha256(modelFile);
    return actualHash.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Downloads model using atomic staging (.part file), byte-range resume headers,
  /// Downloads a GGUF model from HuggingFace with HTTP Range header resume support
  /// and SHA-256 verification before renaming to the final .gguf file.
  Future<Either<Failure, File>> downloadModelWithResume({
    required LocalModelInfo modelInfo,
    required Directory destinationDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    void Function(String speed, String eta)? onSpeedAndEta,
    void Function(bool isVerifying)? onVerifying,
    Dio? dioClient,
  });
}

class SupabaseModelRepository extends ModelRepository {
  final SupabaseClient? client;

  SupabaseModelRepository([this.client]);

  @override
  Future<Either<Failure, AppConfig?>> getLatestModelConfig() async {
    final c = client;
    if (c == null) {
      return const Right(null);
    }
    try {
      final response = await c
          .from('app_config')
          .select()
          .eq('key', 'latest_model_version')
          .maybeSingle();

      if (response == null) {
        return const Right(null);
      }

      final config = AppConfig.fromJson(response);
      return Right(config);
    } catch (e) {
      // Return unexpected failure but allow app to continue with local model
      return const Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, File>> downloadModelWithResume({
    required LocalModelInfo modelInfo,
    required Directory destinationDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    void Function(String speed, String eta)? onSpeedAndEta,
    void Function(bool isVerifying)? onVerifying,
    Dio? dioClient,
  }) async {
    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(recursive: true);
    }

    final targetFile = File('${destinationDirectory.path}/${modelInfo.fileName}');
    final partFile = File('${destinationDirectory.path}/${modelInfo.fileName}.part');
    final dio = dioClient ?? Dio();

    try {
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      final options = Options(
        responseType: ResponseType.stream,
        headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
      );

      Response<ResponseBody> response;
      try {
        response = await dio.get<ResponseBody>(
          modelInfo.downloadUrl,
          options: options,
        );
      } on DioException catch (dioErr) {
        // If 416 Range Not Satisfiable, clear part file and start from 0
        if (dioErr.response?.statusCode == 416) {
          if (await partFile.exists()) await partFile.delete();
          existingBytes = 0;
          response = await dio.get<ResponseBody>(
            modelInfo.downloadUrl,
            options: Options(responseType: ResponseType.stream),
          );
        } else {
          rethrow;
        }
      }

      final responseBody = response.data;
      if (responseBody == null) {
        return const Left(ServerFailure('Empty response from model server'));
      }

      // Determine total content length
      final contentLengthHeader = response.data?.headers[Headers.contentLengthHeader]?.firstOrNull ??
          response.headers.value(Headers.contentLengthHeader);
      int totalBytes = -1;
      if (contentLengthHeader != null) {
        final parsed = int.tryParse(contentLengthHeader);
        if (parsed != null) {
          totalBytes = existingBytes + parsed;
        }
      }

      final fileSink = partFile.openWrite(
        mode: (existingBytes > 0 && response.statusCode == 206)
            ? FileMode.append
            : FileMode.write,
      );

      int receivedBytes = existingBytes;
      int lastSampleBytes = existingBytes;
      DateTime lastSampleTime = DateTime.now();

      await responseBody.stream.listen((chunk) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null) {
          onProgress(receivedBytes, totalBytes);
        }

        final now = DateTime.now();
        final elapsed = now.difference(lastSampleTime).inMilliseconds;
        if (elapsed >= 500 && onSpeedAndEta != null) {
          final bytesDelta = receivedBytes - lastSampleBytes;
          final bytesPerSec = (bytesDelta / (elapsed / 1000.0));
          final speedMB = (bytesPerSec / (1024 * 1024)).toStringAsFixed(1);
          final speedStr = '$speedMB MB/s';

          String etaStr = '--';
          if (totalBytes > 0 && bytesPerSec > 0) {
            final remainingBytes = totalBytes - receivedBytes;
            final remainingSec = (remainingBytes / bytesPerSec).round();
            if (remainingSec < 60) {
              etaStr = '${remainingSec}s';
            } else {
              etaStr = '${(remainingSec / 60).floor()}m ${remainingSec % 60}s';
            }
          }

          onSpeedAndEta(speedStr, etaStr);
          lastSampleBytes = receivedBytes;
          lastSampleTime = now;
        }
      }).asFuture();

      await fileSink.flush();
      await fileSink.close();

      // ── SHA-256 Verification ───────────────────────────────────────────────
      if (modelInfo.expectedSha256.isNotEmpty) {
        if (onVerifying != null) onVerifying(true);
        final actualSha256 = await calculateSha256(partFile);
        if (onVerifying != null) onVerifying(false);

        if (actualSha256.toLowerCase() != modelInfo.expectedSha256.toLowerCase()) {
          // Corrupt download — delete part file to prevent poisoned state
          if (await partFile.exists()) {
            await partFile.delete();
          }
          return Left(ModelValidationFailure(
            'Model checksum verification failed. The downloaded file is corrupt.',
            modelInfo.expectedSha256,
            actualSha256,
          ));
        }
      }

      // ── Atomic Rename ──────────────────────────────────────────────────────
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);

      return Right(targetFile);
    } catch (e) {
      if (e is ModelValidationFailure) {
        return Left(e);
      }
      // Retain .part file for resume on next attempt
      return Left(ServerFailure('Download interrupted: $e'));
    }
  }
}
