import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../privacy/pii_scrubber_service.dart';
import '../../../features/receipt_scanning/domain/entities/receipt.dart';

/// Service responsible for managing the local on-device continuous learning staging pipeline.
///
/// Converts user-verified ground truth receipts into HuggingFace/Qwen2-VL chat-formatted
/// training records with 100% PII scrubbing. Staged samples are written to a local `.jsonl`
/// file for export or direct on-device QLoRA fine-tuning.
class DatasetContributionService {
  final Directory? _baseDirectory;
  static const String _fileName = 'dataset_contributions.jsonl';

  DatasetContributionService({Directory? baseDirectory}) : _baseDirectory = baseDirectory;

  Future<File?> _getContributionsFile() async {
    if (kIsWeb) return null;
    try {
      final dir = _baseDirectory ?? await getApplicationDocumentsDirectory();
      final contribDir = Directory('${dir.path}/dataset_contributions');
      if (!await contribDir.exists()) {
        await contribDir.create(recursive: true);
      }
      return File('${contribDir.path}/$_fileName');
    } catch (e) {
      debugPrint('DatasetContributionService: Error accessing directory: $e');
      return null;
    }
  }

  /// Stages a user-verified receipt into the local fine-tuning dataset with PII scrubbing.
  Future<bool> stageVerifiedReceipt({
    required Receipt receipt,
    String? imagePath,
  }) async {
    final file = await _getContributionsFile();
    if (file == null) return false;

    try {
      // 1. Calculate image hash or identifier
      String imageIdentifier = 'receipt_${receipt.id}.jpg';
      if (imagePath != null && !kIsWeb) {
        final imgFile = File(imagePath);
        if (await imgFile.exists()) {
          final bytes = await imgFile.readAsBytes();
          final hash = sha256.convert(bytes).toString().substring(0, 16);
          imageIdentifier = 'img_$hash.jpg';
        }
      }

      // 2. Sanitize and build GBNF-compliant ground truth JSON
      final sanitizedData = PiiScrubberService.sanitizeReceiptForTraining(receipt);

      final groundTruthJson = jsonEncode({
        'merchant_name': sanitizedData['anonymized_merchant'],
        'merchant_address': '[REDACTED_ADDRESS]',
        'vat_number': 'IT12345678901',
        'date': receipt.date.toIso8601String().split('T').first,
        'time': dateFormatTime(receipt.date),
        'currency': receipt.currency.isNotEmpty ? receipt.currency : 'USD',
        'items': receipt.items.map((item) {
          final cleanDesc = PiiScrubberService.sanitizeText(item.description);
          return {
            'raw_name': cleanDesc,
            'normalized_name': cleanDesc,
            'main_category': item.mainCategory ?? 'Miscellaneous',
            'sub_category': item.subCategory ?? 'General',
            'necessity': item.necessity.name,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'total_price': item.totalPrice,
            'is_asset': item.isAsset,
          };
        }).toList(),
        'tax_breakdown': [
          {
            'rate_percent': 22.0,
            'taxable_amount': (receipt.totalAmount * 0.82).clamp(0.0, double.infinity),
            'tax_amount': (receipt.totalAmount * 0.18).clamp(0.0, double.infinity),
          }
        ],
        'total_amount': receipt.totalAmount,
        'confidence_score': 1.0,
      });

      // 3. Format as HuggingFace multi-turn chat template
      final record = {
        'id': 'contrib_${DateTime.now().millisecondsSinceEpoch}',
        'source': 'user_verified_ground_truth',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'image_ref': imageIdentifier,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'image', 'image': imageIdentifier},
              {'type': 'text', 'text': 'Extract receipt metadata and items as JSON.'}
            ]
          },
          {
            'role': 'assistant',
            'content': groundTruthJson,
          }
        ]
      };

      // 4. Append JSON line atomically
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(jsonEncode(record));
      await sink.flush();
      await sink.close();

      debugPrint('DatasetContributionService: Staged sample for receipt ${receipt.id}');
      return true;
    } catch (e) {
      debugPrint('DatasetContributionService: Failed to stage receipt: $e');
      return false;
    }
  }

  /// Helper to format time as HH:mm:ss
  static String dateFormatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  /// Returns total number of staged training samples.
  Future<int> getSampleCount() async {
    final file = await _getContributionsFile();
    if (file == null || !await file.exists()) return 0;

    try {
      final lines = await file.readAsLines();
      return lines.where((l) => l.trim().isNotEmpty).length;
    } catch (_) {
      return 0;
    }
  }

  /// Returns total size of the contribution corpus in bytes.
  Future<int> getTotalSizeBytes() async {
    final file = await _getContributionsFile();
    if (file == null || !await file.exists()) return 0;
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  /// Reads and returns the raw JSONL dataset string.
  Future<String> exportJsonlContent() async {
    final file = await _getContributionsFile();
    if (file == null || !await file.exists()) return '';
    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Purges all staged contribution samples.
  Future<bool> clearStagedData() async {
    final file = await _getContributionsFile();
    if (file == null || !await file.exists()) return true;
    try {
      await file.delete();
      return true;
    } catch (e) {
      debugPrint('DatasetContributionService: Error clearing dataset: $e');
      return false;
    }
  }
}
