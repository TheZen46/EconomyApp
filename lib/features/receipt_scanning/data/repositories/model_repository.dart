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

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sizeLabel,
    required this.downloadUrl,
    required this.expectedSha256,
  });

  /// Official Gemma 2B IT GGUF model endpoint & expected SHA-256 checksum
  static const gemma2b = LocalModelInfo(
    id: 'gemma-2b-it',
    name: 'Gemma 2B IT',
    fileName: 'gemma-2b-it.Q4_K_M.gguf',
    sizeLabel: '~1.47 GB',
    downloadUrl:
        'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it.Q4_K_M.gguf?download=true',
    expectedSha256:
        'e29d72dfbf2e9bcba97fef2b860655bf965c71a3962d3e1dbf3ca3e50a7c490a',
  );

  static const defaultModel = gemma2b;
}

abstract class ModelRepository {
  Future<Either<Failure, AppConfig?>> getLatestModelConfig();
  LocalModelInfo get defaultModelInfo => LocalModelInfo.defaultModel;

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
  /// and SHA-256 verification before renaming to the final .gguf file.
  Future<Either<Failure, File>> downloadModelWithResume({
    required LocalModelInfo modelInfo,
    required Directory destinationDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    Dio? dioClient,
  });
}

class SupabaseModelRepository extends ModelRepository {
  final SupabaseClient client;

  SupabaseModelRepository(this.client);

  @override
  Future<Either<Failure, AppConfig?>> getLatestModelConfig() async {
    try {
      final response = await client
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

      await responseBody.stream.listen((chunk) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null) {
          onProgress(receivedBytes, totalBytes);
        }
      }).asFuture();

      await fileSink.flush();
      await fileSink.close();

      // ── SHA-256 Verification ───────────────────────────────────────────────
      if (modelInfo.expectedSha256.isNotEmpty) {
        final actualSha256 = await calculateSha256(partFile);
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
