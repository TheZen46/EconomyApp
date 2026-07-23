// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:hive/hive.dart';
import '../../../../core/error/failures.dart';
import '../models/receipt_model.dart';

abstract class LocalReceiptDataSource {
  Future<List<ReceiptModel>> getReceipts();
  Future<void> saveReceipt(ReceiptModel receipt);
  Future<void> clearAll();
  Future<void> deleteReceipt(String id);
}

class HiveReceiptDataSourceImpl implements LocalReceiptDataSource {
  final Box<ReceiptModel> receiptBox;

  HiveReceiptDataSourceImpl(this.receiptBox);

  @override
  Future<List<ReceiptModel>> getReceipts() async {
    try {
      return receiptBox.values.toList();
    } catch (e) {
      throw const CacheFailure();
    }
  }

  @override
  Future<void> saveReceipt(ReceiptModel receipt) async {
    try {
      await receiptBox.put(receipt.id, receipt);
    } catch (e) {
      throw const CacheFailure();
    }
  }

  @override
  Future<void> clearAll() async {
    await receiptBox.clear();
  }

  @override
  Future<void> deleteReceipt(String id) async {
    await receiptBox.delete(id);
  }
}
