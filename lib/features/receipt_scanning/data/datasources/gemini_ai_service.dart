import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../domain/entities/receipt.dart';
import '../models/receipt_model.dart';
import '../../../../core/constants/taxonomy_constants.dart';

class GeminiAIService implements AIService {
  final String apiKey;
  late final GenerativeModel _model;

  GeminiAIService(this.apiKey) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        return const Left(CacheFailure("Image file not found"));
      }

      final imageBytes = await file.readAsBytes();
      
      // Dynamic Taxonomy Generation
      final effectiveTaxonomy = taxonomy ?? TaxonomyConstants.hierarchy;
      final taxonomyBuffer = StringBuffer();
      effectiveTaxonomy.forEach((main, subs) {
         final subList = subs.keys.join(', ');
         taxonomyBuffer.writeln('         - $main: [$subList]');
      });

      final prompt = TextPart("""
      You are an expert receipt extraction AI. 
      Analyze the receipt image and extract the following data into a strict JSON format.
      
      Required Fields:
      - merchant: { name: String, vat_number: String (optional), address: String (optional) }
      - transaction: { date: String (ISO8601 YYYY-MM-DD), time: String (HH:mm), total_amount: Number, currency: String (Symbol like €, \$, £) }
      - items: [ 
          { 
            description: String, 
            unit_price: Number, 
            quantity: Integer, 
            total_price: Number (optional), 
            
            // TAXONOMY FIELDS
            necessity: String, // 'essential', 'discretional', or 'junk'
            main_category: String, 
            sub_category: String 
          } 
        ]

      TAXONOMY RULES:
      
      1. NECESSITY (Choose One):
         - 'essential': Survival (Veg, Meat, Hygiene).
         - 'discretional': Comfort (Coffee, Treats, Decor).
         - 'junk': Unhealthy/Wasteful (Soda, Candy, Alcohol).
         
      2. CATEGORIZATION (Use this exact hierarchy):
${taxonomyBuffer.toString()}

      3. IMPORTANT MAPPING EXAMPLES:
         - Soda/Chips/Candy -> 'junk', Main='Snacks & Drinks'
         - Water/Basics -> 'essential', Main='Food & Drink' or 'Pantry'
         - Alcohol -> 'junk' (or discretional if fancy wine, but default junk for consistency)
         
      Rules:
      1. Use inference if fields are missing.
      2. Return ONLY raw JSON. No markdown backticks.
      """);

      final imagePart = DataPart('image/jpeg', imageBytes); // Assuming jpeg for complexity, or detect mime

      final content = [
        Content.multi([prompt, imagePart])
      ];

      final response = await _model.generateContent(content);
      
      if (response.text == null) {
        return const Left(CacheFailure("AI returned empty response"));
      }

      // Clean response (remove markdown if present)
      final cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
      
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(cleanJson);
        
        // Use ReceiptModel.fromJson logic to parse
        final receiptModel = ReceiptModel.fromJson(jsonMap);
        
        // Assign the correct image path (Model gen creates a dummy ID, preserve it or new?)
        // The ID is generated in fromJson.
        
        return Right(receiptModel.toEntity().copyWith(imagePath: imagePath));

      } catch (e) {
        print("Gemini JSON Parse Error: $e");
        print("Raw Response: ${response.text}");
        return const Left(AIProcessingFailure("Failed to parse AI JSON"));
      }
    } catch (e) {
      print("Gemini AI Error: $e");
      if (e.toString().contains('Quota exceeded')) {
         return const Left(ServerFailure("AI Quota Exceeded. Please wait a moment."));
      }
      return Left(ServerFailure(e.toString()));
    }
  }
}
