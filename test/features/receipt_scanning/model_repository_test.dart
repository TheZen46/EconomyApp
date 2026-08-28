import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';

class FakeResponseBodyDio extends Fake implements Dio {
  final List<int> responseBytes;
  final bool shouldFailChecksum;
  int getCallCount = 0;
  String? lastRangeHeader;

  FakeResponseBodyDio(this.responseBytes, {this.shouldFailChecksum = false});

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    getCallCount++;
    lastRangeHeader = options?.headers?['Range'] as String?;

    int startOffset = 0;
    if (lastRangeHeader != null && lastRangeHeader!.startsWith('bytes=')) {
      final rangeStr = lastRangeHeader!.substring(6).replaceAll('-', '');
      startOffset = int.tryParse(rangeStr) ?? 0;
    }

    final chunk = responseBytes.sublist(startOffset.clamp(0, responseBytes.length));
    final stream = Stream<Uint8List>.fromIterable([Uint8List.fromList(chunk)]);
    final responseBody = ResponseBody(
      stream,
      startOffset > 0 ? 206 : 200,
      headers: {
        Headers.contentLengthHeader: [chunk.length.toString()],
      },
    );

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: responseBody as T,
      statusCode: startOffset > 0 ? 206 : 200,
    );
  }
}

class FakeSupabaseClient extends Fake implements SupabaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SupabaseModelRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_repo_test_');
    repository = SupabaseModelRepository(FakeSupabaseClient());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelRepository - Model Metadata & Integrity Verification', () {
    test('LocalModelInfo.gemma2b points to official HuggingFace endpoint with matching metadata', () {
      const gemma = LocalModelInfo.gemma2b;
      expect(gemma.name, 'Gemma 2B IT');
      expect(gemma.fileName, 'gemma-2b-it.Q4_K_M.gguf');
      expect(gemma.downloadUrl.contains('huggingface.co/google/gemma-2b-it-GGUF'), isTrue);
      expect(gemma.expectedSha256, isNotEmpty);
    });

    test('calculateSha256 and verifyModelIntegrity accurately validate matching files', () async {
      final testFile = File('${tempDir.path}/test_model.gguf');
      const testContent = 'GGUF_HEADER_VALID_DATA_PAYLOAD_12345';
      await testFile.writeAsString(testContent);

      final expectedHash = sha256.convert(utf8.encode(testContent)).toString();
      final calculated = await repository.calculateSha256(testFile);

      expect(calculated, expectedHash);
      final isValid = await repository.verifyModelIntegrity(testFile, expectedHash);
      expect(isValid, isTrue);

      final isInvalid = await repository.verifyModelIntegrity(testFile, '00000000000000000000000000000000');
      expect(isInvalid, isFalse);
    });

    test('verifyModelIntegrity returns false for empty or non-existent files', () async {
      final missingFile = File('${tempDir.path}/missing.gguf');
      expect(await repository.verifyModelIntegrity(missingFile, 'any_hash'), isFalse);

      final emptyFile = File('${tempDir.path}/empty.gguf');
      await emptyFile.create();
      expect(await repository.verifyModelIntegrity(emptyFile, 'any_hash'), isFalse);
    });
  });

  group('ModelRepository - Atomic Resumable Downloads & Checksum Validation', () {
    test('successful download stages in .part file and atomically renames to .gguf upon checksum verification', () async {
      const payload = 'VALID_MODEL_WEIGHTS_BINARY_BLOB_FOR_GEMMA_2B';
      final payloadBytes = utf8.encode(payload);
      final expectedSha = sha256.convert(payloadBytes).toString();

      final modelInfo = LocalModelInfo(
        id: 'test-gemma',
        name: 'Gemma 2B Test',
        fileName: 'test-gemma.gguf',
        sizeLabel: '1 KB',
        downloadUrl: 'https://example.com/test-gemma.gguf',
        expectedSha256: expectedSha,
      );

      final fakeDio = FakeResponseBodyDio(payloadBytes);

      int lastReceived = 0;
      int lastTotal = 0;

      final result = await repository.downloadModelWithResume(
        modelInfo: modelInfo,
        destinationDirectory: tempDir,
        dioClient: fakeDio,
        onProgress: (received, total) {
          lastReceived = received;
          lastTotal = total;
        },
      );

      expect(result.isRight(), isTrue);
      final finalFile = result.getOrElse(() => throw StateError('Failed'));
      expect(await finalFile.exists(), isTrue);
      expect(finalFile.path.endsWith('test-gemma.gguf'), isTrue);

      // Verify staging .part file is gone
      final partFile = File('${tempDir.path}/test-gemma.gguf.part');
      expect(await partFile.exists(), isFalse);

      // Verify progress was recorded
      expect(lastReceived, payloadBytes.length);
      expect(lastTotal, payloadBytes.length);
    });

    test('corrupted download fails checksum, deletes .part file, and emits ModelValidationFailure', () async {
      const corruptPayload = 'CORRUPTED_TAMPERED_MODEL_BYTES';
      final corruptBytes = utf8.encode(corruptPayload);
      const expectedSha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

      final modelInfo = LocalModelInfo(
        id: 'corrupt-gemma',
        name: 'Gemma 2B Corrupt',
        fileName: 'corrupt-gemma.gguf',
        sizeLabel: '1 KB',
        downloadUrl: 'https://example.com/corrupt-gemma.gguf',
        expectedSha256: expectedSha,
      );

      final fakeDio = FakeResponseBodyDio(corruptBytes);

      final result = await repository.downloadModelWithResume(
        modelInfo: modelInfo,
        destinationDirectory: tempDir,
        dioClient: fakeDio,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ModelValidationFailure>());
          final validationFailure = failure as ModelValidationFailure;
          expect(validationFailure.expectedChecksum, expectedSha);
        },
        (_) => fail('Expected ModelValidationFailure'),
      );

      // Verify corrupt files are purged
      final targetFile = File('${tempDir.path}/corrupt-gemma.gguf');
      final partFile = File('${tempDir.path}/corrupt-gemma.gguf.part');
      expect(await targetFile.exists(), isFalse);
      expect(await partFile.exists(), isFalse);
    });

    test('interrupted download resumes from existing .part byte offset', () async {
      const fullPayload = 'PART1_DOWNLOADED_CHUNK_PART2_REMAINING_CHUNK_DATA';
      final fullBytes = utf8.encode(fullPayload);
      final expectedSha = sha256.convert(fullBytes).toString();

      final modelInfo = LocalModelInfo(
        id: 'resume-gemma',
        name: 'Gemma 2B Resume',
        fileName: 'resume-gemma.gguf',
        sizeLabel: '1 KB',
        downloadUrl: 'https://example.com/resume-gemma.gguf',
        expectedSha256: expectedSha,
      );

      // Pre-seed .part file with first 10 bytes
      final partFile = File('${tempDir.path}/resume-gemma.gguf.part');
      await partFile.writeAsBytes(fullBytes.sublist(0, 10));

      final fakeDio = FakeResponseBodyDio(fullBytes);

      final result = await repository.downloadModelWithResume(
        modelInfo: modelInfo,
        destinationDirectory: tempDir,
        dioClient: fakeDio,
      );

      expect(result.isRight(), isTrue);
      expect(fakeDio.lastRangeHeader, 'bytes=10-');

      final finalFile = result.getOrElse(() => throw StateError('Failed'));
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.readAsString(), fullPayload);
    });
  });
}
