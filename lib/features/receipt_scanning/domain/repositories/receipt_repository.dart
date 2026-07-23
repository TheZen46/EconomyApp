// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/receipt.dart';
import '../../../../core/constants/taxonomy_constants.dart';

abstract class ReceiptRepository {
  Future<Either<Failure, List<Receipt>>> getReceipts();
  Future<Either<Failure, void>> saveReceipt(Receipt receipt);
  Future<Either<Failure, Receipt>> processReceiptImage(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy});
  Future<Either<Failure, void>> syncCorrectedReceipt(Receipt receipt, String imagePath);
  Future<Either<Failure, void>> clearAllData({bool includeCloud = false});
  Future<Either<Failure, void>> deleteReceipt(String id);
}
