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
