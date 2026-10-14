import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../features/receipt_scanning/domain/entities/receipt.dart';
import 'receipt_vlm_schema.dart';

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
    Receipt? originalAiReceipt,
    bool? isUserCorrected,
    bool? originalAiPredictionWasWrong,
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

      // 2. Determine actual user correction flags
      final effectiveIsUserCorrected = isUserCorrected ??
          (originalAiReceipt != null
              ? ReceiptVlmSchema.hasUserCorrections(originalAiReceipt, receipt)
              : receipt.isUserCorrected);
      final effectiveWasAiWrong = originalAiPredictionWasWrong ?? effectiveIsUserCorrected;

      // 3. Build GBNF-compliant ground truth JSON via canonical schema
      final groundTruthMap = ReceiptVlmSchema.toTrainingJson(receipt, anonymize: true);
      final groundTruthJson = jsonEncode(groundTruthMap);

      // 4. Format as HuggingFace multi-turn chat template
      final record = {
        'id': const Uuid().v4(),
        'source': 'user_verified_ground_truth',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'image_ref': imageIdentifier,
        'is_user_corrected': effectiveIsUserCorrected,
        'original_ai_prediction_was_wrong': effectiveWasAiWrong,
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

      // 5. Append JSON line atomically
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

  /// Helper to format time as HH:mm
  static String dateFormatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
