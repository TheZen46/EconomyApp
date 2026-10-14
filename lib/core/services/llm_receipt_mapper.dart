import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../data_contracts/ai_receipt_parser.dart';

/// Maps the JSON produced by the on-device LLM to a [Receipt].
///
/// Delegates to the unified [AiReceiptParser] to guarantee zero schema drift
/// across AI extraction engines.
class LlmReceiptMapper {
  LlmReceiptMapper._();

  /// Maps the model output to a [Receipt].
  static Receipt map(Map<String, dynamic> json, String imagePath, {DateTime? now}) {
    return AiReceiptParser.parseToEntity(json, imagePath: imagePath, now: now);
  }
}
