import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/app_config.dart';
import 'package:t_aidy/features/receipt_scanning/data/repositories/model_repository.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/model_update_provider.dart';

class _ConfigRepository extends ModelRepository {
  final AppConfig config;

  _ConfigRepository(this.config);

  @override
  Future<Either<Failure, AppConfig?>> getLatestModelConfig() async => Right(config);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serves fixed bytes for every download and records the requested URLs.
class _FakeDio extends Fake implements Dio {
  final List<int> body;
  final List<String> requested = [];

  _FakeDio(this.body);

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    requested.add(urlPath);
    await File(savePath as String).writeAsBytes(body);
    return Response(requestOptions: RequestOptions(path: urlPath), statusCode: 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final modelBytes = utf8.encode('GGUF model bytes');
  final modelSha256 = sha256.convert(modelBytes).toString();

  group('ModelUpdateService.validateUpdate', () {
    Map<String, dynamic> metadata({String url = 'https://models.example.com/qwen.gguf', String? hash}) =>
        {'download_url': url, 'hash': hash ?? modelSha256};

    test('accepts an HTTPS update with a version and a SHA-256 digest', () {
      final update = ModelUpdateService.validateUpdate('2.1.0', metadata());
      expect(update, isNotNull);
      expect(update!.sha256, modelSha256);
    });

    test('rejects plain HTTP, missing or malformed digests and unsafe versions', () {
      expect(ModelUpdateService.validateUpdate('2.1.0', metadata(url: 'http://models.example.com/qwen.gguf')), isNull);
      expect(ModelUpdateService.validateUpdate('2.1.0', {'download_url': 'https://models.example.com/q.gguf'}), isNull);
      expect(ModelUpdateService.validateUpdate('2.1.0', metadata(hash: 'abc123')), isNull);
      expect(ModelUpdateService.validateUpdate('9.0.0/../../evil', metadata()), isNull);
      expect(ModelUpdateService.validateUpdate('2.1', metadata()), isNull);
    });
  });

  group('ModelUpdateService.checkForUpdates', () {
    late Directory modelsDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      modelsDir = await Directory.systemTemp.createTemp('model_update_');
    });

    tearDown(() async {
      if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
    });

    ModelUpdateService service(Map<String, dynamic> metadata, _FakeDio dio) {
      return ModelUpdateService(
        _ConfigRepository(AppConfig(key: 'latest_model_version', value: '2.0.0', metadata: metadata)),
        dio: dio,
        modelsDirectory: () async => modelsDir,
      );
    }

    test('an update without a digest is not downloaded', () async {
      final dio = _FakeDio(modelBytes);
      final updater = service({'download_url': 'https://models.example.com/qwen.gguf'}, dio);

      await updater.checkForUpdates();

      expect(dio.requested, isEmpty);
      expect(updater.state.error, contains('rejected'));
      expect(modelsDir.listSync(), isEmpty);
    });

    test('a download whose digest does not match is discarded', () async {
      final dio = _FakeDio(utf8.encode('tampered bytes'));
      final updater = service({'download_url': 'https://models.example.com/qwen.gguf', 'hash': modelSha256}, dio);

      await updater.checkForUpdates();

      expect(dio.requested, hasLength(1));
      expect(updater.state.error, contains('integrity'));
      expect(modelsDir.listSync(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_model_version'), isNull);
    });

    test('a verified download is installed and its version recorded', () async {
      final dio = _FakeDio(modelBytes);
      final updater = service({'download_url': 'https://models.example.com/qwen.gguf', 'hash': modelSha256}, dio);

      await updater.checkForUpdates();

      expect(updater.state.error, isNull);
      expect(File('${modelsDir.path}/qwen2_vl_v2.0.0.gguf').readAsBytesSync(), modelBytes);
      expect(File('${modelsDir.path}/qwen2_vl_v2.0.0.gguf.part').existsSync(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_model_version'), '2.0.0');
    });
  });
}
