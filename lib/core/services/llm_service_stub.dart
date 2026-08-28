import 'dart:async';
import 'package:dartz/dartz.dart';
import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../error/failures.dart';
import 'ai_service.dart';
import '../../core/constants/taxonomy_constants.dart';

class LLMService implements AIService {
  bool get isModelLoaded => false;

  Future<void> initialize() async {}

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    return const Left(CacheFailure());
  }

  Future<String> extractTextFromImage(String path) async {
    return "Not supported on Web";
  }

  static Future<String> generateReceiptData(String prompt, String modelPath) async {
    return "Not supported on Web";
  }

  Stream<String> generate(String prompt) async* {
    yield "Not supported on Web";
  }

  void unload() {}
}
