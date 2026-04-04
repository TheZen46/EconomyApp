import 'dart:async';
import 'dart:convert';
import 'dart:io'; 
import 'package:dartz/dartz.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../error/failures.dart';
import 'ai_service.dart';
import '../../core/constants/taxonomy_constants.dart';

class LLMService implements AIService {
  Llama? _llama;
  bool _isModelLoaded = false;
  
  bool get isModelLoaded => _isModelLoaded;

  Future<void> initialize() async {
     try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/models');
      final modelPath = '${modelDir.path}/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf'; 
      
      if (File(modelPath).existsSync()) {
          print('LLM: Loading model from $modelPath');
          _llama = Llama(modelPath);
          _isModelLoaded = true;
          print('LLM: Loaded');
      }
    } catch (e) {
      print('LLM: Init Error: $e');
    }
  }

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    if (!_isModelLoaded) return const Left(CacheFailure()); 
    
    try {
      // 1. OCR
      final text = await extractTextFromImage(imagePath);
      
      // 2. Prompt LLM
      // 2. Prompt LLM (TinyLlama Format)
      final prompt = """<|system|>
You are a receipt scanning assistant. Extract the following fields from the text into a JSON object: merchantName, date, totalAmount, currency, items (array of description, quantity, unitPrice).
Output strictly JSON.

Example Input:
"Walmart 01/15/2024 Total: 25.50 USD
1x Milk 2.50
2x Bread 3.00"

Example Output:
{
  "merchantName": "Walmart",
  "date": "2024-01-15",
  "totalAmount": 25.50,
  "currency": "USD",
  "items": [
    {"description": "Milk", "quantity": 1, "unitPrice": 2.50},
    {"description": "Bread", "quantity": 2, "unitPrice": 3.00}
  ]
}
</s>
<|user|>
Receipt Text:
$text
</s>
<|assistant|>
""";
      
      // Generation
      _llama!.setPrompt(prompt);
      final buffer = StringBuffer();
      
      while (true) {
        final (token, done) = _llama!.getNext();
        buffer.write(token);
        if (done) break;
        await Future.delayed(Duration.zero); // Yield to event loop to avoid freezing UI
      }

      final fullResponse = buffer.toString();
      print('LLM Raw Response: $fullResponse');
      
      // 3. Parse JSON
      final jsonBlock = _extractJson(fullResponse);
      print('LLM JSON Block: $jsonBlock');
      final data = jsonDecode(jsonBlock);
      
      return Right(_mapToReceipt(data, imagePath)); 
    } catch (e) {
      print('LLM Extract Error: $e');
      return const Left(CacheFailure());
    }
  }
  
  String _extractJson(String text) {
     final start = text.indexOf('{');
     final end = text.lastIndexOf('}');
     if (start != -1 && end != -1) {
       return text.substring(start, end + 1);
     }
     return "{}";
  }

  Receipt _mapToReceipt(Map<String, dynamic> json, String imagePath) {
    return Receipt(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      merchantName: json['merchantName'] ?? 'Unknown',
      date: DateTime.now(), 
      totalAmount: (json['totalAmount'] is num) ? (json['totalAmount'] as num).toDouble() : 0.0,
      currency: json['currency'] ?? 'EUR',
      items: _mapItems(json['items']), 
      imagePath: imagePath,
    );
  }

  List<ReceiptItem> _mapItems(dynamic itemsJson) {
    if (itemsJson is! List) return [];
    
    return itemsJson.map((item) {
       final desc = item['description']?.toString() ?? 'Unknown Item';
       final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
       final unitPrice = (item['unitPrice'] is num) ? (item['unitPrice'] as num).toDouble() : 0.0;
       
       return ReceiptItem(
         description: desc,
         quantity: qty,
         unitPrice: unitPrice,
         totalPrice: qty * unitPrice,
       );
    }).toList();
  }
  
  // OCR Step
  Future<String> extractTextFromImage(String path) async {
     print('OCR: Starting for $path');
     if (Platform.isAndroid || Platform.isIOS) {
       try {
         final inputImage = InputImage.fromFilePath(path);
         final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
         final recognizedText = await textRecognizer.processImage(inputImage);
         await textRecognizer.close();
         print('OCR Success: ${recognizedText.text.substring(0, minimum(recognizedText.text.length, 100))}...');
         return recognizedText.text;
       } catch (e) {
         print('OCR Error: $e');
         return "Error extracting text";
       }
     }
     return "Simulated Receipt Text: \nMerchant: Local Store\nDate: 2024-01-01\nTotal: 25.00 EUR\nItems:\n1x Appless - 5.00\n2x Banana - 10.00";
  }

  int minimum(int a, int b) => (a < b) ? a : b;

  Stream<String> generate(String prompt) async* {
     if (!_isModelLoaded) {
       yield "Error: Model not loaded";
       return;
     }
     _llama!.setPrompt(prompt);
     while (true) {
       final (token, done) = _llama!.getNext();
       yield token;
       if (done) break;
     }
  }

  void unload() {
    _llama?.dispose();
    _llama = null;
    _isModelLoaded = false;
  }
}
