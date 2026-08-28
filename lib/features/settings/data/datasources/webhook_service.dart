import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/data/models/receipt_model.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/error_handler.dart';

class WebhookService {
  final Box settingsBox;
  final Dio _dio;

  WebhookService(this.settingsBox, [Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
            ));

  Future<void> sendWebhook(Receipt receipt) async {
    if (!settingsBox.get('webhook_enabled', defaultValue: false)) {
      throw const WebhookFailure('Webhook is disabled');
    }

    final url = settingsBox.get('webhook_url', defaultValue: '') as String;
    if (url.isEmpty) return;

    // Read secret from secure storage, not Hive
    final secret = await SecureStorageService.readSecret(SecretKeys.webhookSecret) ?? '';

    final options = Options(
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'tAIdy/1.0',
        if (secret.isNotEmpty) 'X-Auth-Secret': secret,
      },
    );

    final payload = ReceiptModel.fromEntity(receipt).toJson();

    try {
      debugPrint('Webhook: Sending receipt ${receipt.id} to $url');
      await _dio.post(url, data: payload, options: options);
      debugPrint('Webhook: Success');
    } catch (e) {
      debugPrint('Webhook: Failed - $e');
      throw ErrorHandler.mapException(e);
    }
  }

  Future<void> sendTestEvent() async {
    if (!settingsBox.get('webhook_enabled', defaultValue: false)) {
      throw const WebhookFailure('Webhook is disabled');
    }

    final url = settingsBox.get('webhook_url', defaultValue: '') as String;
    if (url.isEmpty) {
      throw const WebhookFailure('No webhook URL configured');
    }

    // Read secret from secure storage, not Hive
    final secret = await SecureStorageService.readSecret(SecretKeys.webhookSecret) ?? '';

    final options = Options(
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'tAIdy/1.0',
        if (secret.isNotEmpty) 'X-Auth-Secret': secret,
      },
    );

    final payload = {
      'event': 'test_ping',
      'timestamp': DateTime.now().toIso8601String(),
      'app': 'tAIdy',
      'message': 'This is verified connection from tAIdy.',
    };

    try {
      await _dio.post(url, data: payload, options: options);
    } catch (e) {
      debugPrint('Webhook test: Failed - $e');
      throw ErrorHandler.mapException(e);
    }
  }
}
