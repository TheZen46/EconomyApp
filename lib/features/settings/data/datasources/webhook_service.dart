// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/data/models/receipt_model.dart';

class WebhookService {
  final Box settingsBox;
  final Dio _dio;

  WebhookService(this.settingsBox) : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
  ));

  Future<void> sendWebhook(Receipt receipt) async {
    if (!settingsBox.get('webhook_enabled', defaultValue: false)) throw Exception('Webhook disabled');

    final url = settingsBox.get('webhook_url', defaultValue: '') as String;
    if (url.isEmpty) return;

    final secret = settingsBox.get('webhook_secret', defaultValue: '') as String;
    
    final options = Options(
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'tAIdy/1.0',
        if (secret.isNotEmpty) 'X-Auth-Secret': secret,
      },
    );

    final payload = ReceiptModel.fromEntity(receipt).toJson();

    try {
      print('Webhook: Sending receipt ${receipt.id} to $url');
      await _dio.post(url, data: payload, options: options);
      print('Webhook: Success');
    } catch (e) {
      print('Webhook: Failed - $e');
      // We assume the caller handles retry/queueing logic if needed, 
      // or we just log and ignore for "fire and forget" if it's not critical sync.
      // For now, mirroring "The Connector" philosophy: it's a best-effort push.
      rethrow;
    }
  }

  Future<void> sendTestEvent() async {
    if (!settingsBox.get('webhook_enabled', defaultValue: false)) throw Exception('Webhook disabled');
    final url = settingsBox.get('webhook_url', defaultValue: '') as String;
    
    if (url.isEmpty) throw Exception('No URL configured');

    final secret = settingsBox.get('webhook_secret', defaultValue: '') as String;

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

    await _dio.post(url, data: payload, options: options);
  }
}
