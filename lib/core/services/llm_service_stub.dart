// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
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

  Stream<String> generate(String prompt) async* {
    yield "Not supported on Web";
  }

  void unload() {}
}
