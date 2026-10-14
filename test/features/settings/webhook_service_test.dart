import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/privacy/network_policy.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/settings/data/datasources/webhook_service.dart';

class ErrorInterceptor extends Interceptor {
  final DioException errorToThrow;
  ErrorInterceptor(this.errorToThrow);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(errorToThrow);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box settingsBox;
  late Map<String, String> secureStore;

  setUp(() async {
    secureStore = {};
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      final args = (methodCall.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (methodCall.method) {
        case 'read':
          return secureStore[key];
        case 'write':
          secureStore[key!] = args['value'] as String;
          return null;
        case 'delete':
          secureStore.remove(key);
          return null;
      }
      return null;
    });

    tempDir = await Directory.systemTemp.createTemp('webhook_test_dir_');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox('test_webhook_settings');
  });

  tearDown(() async {
    await settingsBox.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WebhookService - Error Mapping & Failure Domain Types', () {
    test('throws WebhookFailure when webhook is disabled', () async {
      final webhookService = WebhookService(settingsBox);
      await settingsBox.put('webhook_enabled', false);

      expect(
        () => webhookService.sendTestEvent(),
        throwsA(isA<WebhookFailure>().having((f) => f.message, 'message', 'Webhook is disabled')),
      );
    });

    test('throws WebhookFailure when URL is empty', () async {
      final webhookService = WebhookService(settingsBox);
      await settingsBox.put('webhook_enabled', true);
      secureStore['webhook_url'] = '';

      expect(
        () => webhookService.sendTestEvent(),
        throwsA(isA<WebhookFailure>().having((f) => f.message, 'message', 'No webhook URL configured')),
      );
    });

    test('maps connection error to NetworkFailure domain type on test ping', () async {
      final dio = Dio();
      dio.interceptors.add(ErrorInterceptor(
        DioException(
          requestOptions: RequestOptions(path: '/webhook'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        ),
      ));

      final webhookService = WebhookService(settingsBox, dio);
      await settingsBox.put('webhook_enabled', true);
      secureStore['webhook_url'] = 'http://127.0.0.1:54321/webhook';

      expect(
        () => webhookService.sendTestEvent(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('maps HTTP 500 error to WebhookFailure domain type on sendWebhook', () async {
      final dio = Dio();
      dio.interceptors.add(ErrorInterceptor(
        DioException(
          requestOptions: RequestOptions(path: '/webhook'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/webhook'),
            statusCode: 500,
          ),
        ),
      ));

      final webhookService = WebhookService(settingsBox, dio);
      await settingsBox.put('webhook_enabled', true);
      secureStore['webhook_url'] = 'http://127.0.0.1:54321/webhook';

      final receipt = Receipt(
        id: 'rec-test-01',
        merchantName: 'Test Merchant',
        totalAmount: 99.99,
        date: DateTime.now(),
        items: [],
        currency: 'USD',
      );

      expect(
        () => webhookService.sendWebhook(receipt),
        throwsA(isA<WebhookFailure>().having((f) => f.statusCode, 'statusCode', 500)),
      );
    });

    test('reads the URL from secure storage, where the startup migration moves it', () async {
      final dio = Dio();
      dio.interceptors.add(ErrorInterceptor(
        DioException(
          requestOptions: RequestOptions(path: '/webhook'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        ),
      ));
      final webhookService = WebhookService(settingsBox, dio);
      await settingsBox.put('webhook_enabled', true);
      // A value left in the settings box by an earlier version is not consulted.
      await settingsBox.put('webhook_url', 'http://legacy.invalid/webhook');

      await expectLater(
        webhookService.sendTestEvent(),
        throwsA(isA<WebhookFailure>().having((f) => f.message, 'message', 'No webhook URL configured')),
      );

      secureStore['webhook_url'] = 'http://127.0.0.1:54321/webhook';
      await expectLater(webhookService.sendTestEvent(), throwsA(isA<NetworkFailure>()));
    });
  });

  group('WebhookService - isolation mode', () {
    test('sends nothing while isolation mode is on', () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          requests.add(options);
          handler.reject(DioException(requestOptions: options));
        }));
      final webhookService = WebhookService(settingsBox, dio);
      await settingsBox.put('webhook_enabled', true);
      await settingsBox.put(NetworkPolicy.isolationModeKey, true);
      secureStore['webhook_url'] = 'https://hooks.example.com/receipts';

      await expectLater(webhookService.sendTestEvent(), throwsA(isA<WebhookFailure>()));
      await expectLater(
        webhookService.sendWebhook(Receipt(
          id: 'r1',
          merchantName: 'Shop',
          date: DateTime.utc(2026, 9, 1),
          totalAmount: 1,
          currency: 'EUR',
        )),
        throwsA(isA<WebhookFailure>()),
      );
      expect(requests, isEmpty);
    });
  });
}
