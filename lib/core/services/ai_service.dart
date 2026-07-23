// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:dartz/dartz.dart';
import '../error/failures.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';

import '../../core/constants/taxonomy_constants.dart';

abstract class AIService {
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy});
}
