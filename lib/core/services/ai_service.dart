import 'package:dartz/dartz.dart';
import '../error/failures.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

import '../../core/constants/taxonomy_constants.dart';

abstract class AIService {
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy});
}
