import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../core/utils/currency_codes.dart';
import '../../../../core/utils/json_parser_utils.dart';
import '../../domain/entities/receipt.dart';
import '../models/receipt_model.dart';
import '../../../../core/constants/taxonomy_constants.dart';

class GeminiAIService implements AIService {
  /// Settings key of an optional model identifier overriding [defaultModel].
  static const String modelSettingKey = 'gemini_model';

  /// Model used when none is configured. The Gemini 1.5 family used before
  /// has been retired; check the current model catalogue when this changes.
  static const String defaultModel = 'gemini-2.5-flash';

  final String apiKey;
  final String modelName;
  late final GenerativeModel _model;

  GeminiAIService(this.apiKey, {String? model})
      : modelName = (model == null || model.trim().isEmpty) ? defaultModel : model.trim() {
    _model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      // Structured output: the response body is JSON, without prose or fences.
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
  }

  /// MIME type of an image from its file signature, or null when the format
  /// is not one Gemini accepts (JPEG, PNG, WebP, HEIC/HEIF).
  static String? detectImageMimeType(Uint8List bytes) {
    bool startsWith(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
    if (startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, 8)) return 'image/webp';
    if (startsWith('ftyp'.codeUnits, 4) && bytes.length >= 12) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {'heic', 'heix', 'hevc', 'hevx'}.contains(brand)) return 'image/heic';
      if (const {'mif1', 'msf1', 'heif'}.contains(brand)) return 'image/heif';
    }
    return null;
  }

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    try {
      // XFile reads files on native platforms and blob URLs on web.
      final Uint8List imageBytes;
      try {
        imageBytes = await XFile(imagePath).readAsBytes();
      } catch (_) {
        return const Left(CacheFailure("Image file not found"));
      }
      if (imageBytes.isEmpty) {
        return const Left(CacheFailure("Image file not found"));
      }
      final mimeType = detectImageMimeType(imageBytes);
      if (mimeType == null) {
        return const Left(AIProcessingFailure("Unsupported image format. Use JPEG, PNG, WebP or HEIC."));
      }
      
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
      - transaction: { date: String (ISO8601 YYYY-MM-DD), time: String (HH:mm), total_amount: Number, currency: String (ISO 4217 code such as EUR, USD, GBP; never a symbol) }
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

      final imagePart = DataPart(mimeType, imageBytes);

      final content = [
        Content.multi([prompt, imagePart])
      ];

      final response = await _model.generateContent(content);
      
      if (response.text == null) {
        return const Left(CacheFailure("AI returned empty response"));
      }

      // Extract JSON robustly — handles markdown fences, filler text, nested braces
      final jsonMap = JsonParserUtils.extractJsonMap(response.text!);

      if (jsonMap == null) {
        debugPrint("Gemini: Failed to extract JSON from response");
        // The raw response contains receipt content; keep it out of release logs.
        if (kDebugMode) debugPrint("Gemini Raw Response: ${response.text}");
        return const Left(AIProcessingFailure("Failed to parse AI output"));
      }

      try {
        // Use ReceiptModel.fromJson logic to parse
        final receipt = ReceiptModel.fromJson(jsonMap).toEntity();

        return Right(receipt.copyWith(
          imagePath: imagePath,
          // Symbols such as "€" are mapped to their ISO 4217 code.
          currency: CurrencyCodes.normalize(receipt.currency),
        ));

      } catch (e) {
        debugPrint("Gemini JSON Parse Error: $e");
        if (kDebugMode) debugPrint("Raw Response: ${response.text}");
        return const Left(AIProcessingFailure("Failed to parse AI output"));
      }
    } catch (e) {
      debugPrint("Gemini AI Error: $e");
      if (e.toString().contains('Quota exceeded')) {
         return const Left(ServerFailure("AI Quota Exceeded. Please wait a moment."));
      }
      return Left(ServerFailure(e.toString()));
    }
  }
}
