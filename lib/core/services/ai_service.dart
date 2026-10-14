import 'package:dartz/dartz.dart';
import '../error/failures.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../../core/constants/taxonomy_constants.dart';
import 'ai_backend_registry.dart';

/// Abstract contract for an AI extraction service in tAIdy.
abstract class AIService {
  /// Identity, capabilities, privacy tier, and operational readiness descriptor for this backend.
  AiBackendDescriptor get descriptor;

  /// Extracts structured receipt data from an image file at [imagePath].
  Future<Either<Failure, Receipt>> extractReceiptData(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  });
}
