import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../domain/entities/receipt.dart';
import '../models/receipt_model.dart';
import '../../../../core/constants/taxonomy_constants.dart';

class MockAIService implements AIService {
  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    await Future.delayed(const Duration(seconds: 2));

    // "Perfect JSON" Mock Response
    final mockJson = {
      "merchant": {
        "name": "Esselunga",
        "vat_number": "IT12345678901", 
        "address": "Via Roma 1, Milano"
      },
      "transaction": {
        "date": DateTime.now().toIso8601String(),
        "time": "14:30",
        "currency": "EUR",
        "total_amount": 45.50
      },
      "category": "Grocery", 
      "items": [
        {
          "description": "Pasta Barilla 500g",
          "quantity": 2,
          "unit_price": 1.20,
          "total_price": 2.40
        },
        {
          "description": "Coca Cola Zero",
          "quantity": 1,
          "unit_price": 1.50,
          "total_price": 1.50
        }
      ]
    };

    try {
      // Use the Model's logic to parse the Perfect JSON
      final model = ReceiptModel.fromJson(mockJson);
      
      // Add the image path and ID which aren't in the AI response
      final receipt = model.toEntity().copyWith(
        id: const Uuid().v4(),
        imagePath: imagePath,
      );

      return Right(receipt);
    } catch (e) {
      return const Left(AIProcessingFailure());
    }
  }
}
