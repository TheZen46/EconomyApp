import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/receipt_scanning/domain/entities/receipt.dart';
import '../error/failures.dart';
import 'ai_service.dart';
import '../../core/constants/taxonomy_constants.dart';
import '../utils/json_parser_utils.dart';

class LLMService implements AIService {
  bool _isModelLoaded = false;
  String? _modelPath;

  bool get isModelLoaded => _isModelLoaded;

  Future<void> initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/models');
      final gemmaPath = '${modelDir.path}/gemma-2b-it.Q4_K_M.gguf';
      final tinyLlamaPath = '${modelDir.path}/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

      if (File(gemmaPath).existsSync() && File(gemmaPath).lengthSync() > 0) {
        debugPrint('LLM: Gemma 2B Model found at $gemmaPath');
        _modelPath = gemmaPath;
        _isModelLoaded = true;
        debugPrint('LLM: Ready (will load in isolate on demand)');
      } else if (File(tinyLlamaPath).existsSync() && File(tinyLlamaPath).lengthSync() > 0) {
        debugPrint('LLM: TinyLlama Model found at $tinyLlamaPath');
        _modelPath = tinyLlamaPath;
        _isModelLoaded = true;
        debugPrint('LLM: Ready (will load in isolate on demand)');
      } else {
        _isModelLoaded = false;
        _modelPath = null;
      }
    } catch (e) {
      debugPrint('LLM: Init Error: $e');
    }
  }

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(String imagePath, {Map<String, Map<String, List<TaxonomyItem>>>? taxonomy}) async {
    if (!_isModelLoaded || _modelPath == null) return const Left(CacheFailure());

    try {
      // 1. OCR (uses platform channels — must stay on main isolate)
      final text = await extractTextFromImage(imagePath);

      // 2. Build prompt
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

      // 3. Run the entire LLM lifecycle inside a background isolate via generateReceiptData.
      //    The Llama C++ object is created, used, and disposed entirely
      //    within the worker isolate — no native pointers cross the boundary.
      final fullResponse = await generateReceiptData(prompt, _modelPath!);

      debugPrint('LLM Raw Response: $fullResponse');

      // 4. Parse JSON robustly — handles markdown fences, filler text, nested braces
      final data = JsonParserUtils.extractJsonMap(fullResponse);

      if (data == null) {
        debugPrint('LLM: Failed to extract JSON from response');
        return const Left(AIProcessingFailure('Failed to parse AI output'));
      }

      return Right(_mapToReceipt(data, imagePath));
    } catch (e) {
      debugPrint('LLM Extract Error: $e');
      return const Left(AIProcessingFailure('Failed to parse AI output'));
    }
  }

  /// Generates receipt data/JSON by running the entire llama_cpp_dart token
  /// generation loop in a dedicated background isolate via [Isolate.run].
  ///
  /// Initializes, decodes, and safely disposes all native C-bindings and
  /// memory pointers entirely within the background isolate so the main Dart
  /// UI isolate event loop remains 100% free of frame drops and ANR pauses.
  static Future<String> generateReceiptData(String prompt, String modelPath) async {
    return await Isolate.run(() => _runLlamaInIsolate(modelPath, prompt));
  }

  /// Runs the full Llama lifecycle inside an isolate:
  ///   1. Instantiate Llama(modelPath)
  ///   2. setPrompt
  ///   3. Loop getNext() until done
  ///   4. dispose()
  ///   5. Return the complete generated string
  ///
  /// This is a top-level/static function so it can be passed to Isolate.run().
  static String _runLlamaInIsolate(String modelPath, String prompt) {
    final llama = Llama(modelPath);
    try {
      llama.setPrompt(prompt);
      final buffer = StringBuffer();

      while (true) {
        final (token, done) = llama.getNext();
        buffer.write(token);
        if (done) break;
      }

      return buffer.toString();
    } finally {
      llama.dispose();
    }
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

  // OCR Step — must stay on main isolate (uses platform channels)
  Future<String> extractTextFromImage(String path) async {
    debugPrint('OCR: Starting for $path');
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final inputImage = InputImage.fromFilePath(path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();
        debugPrint('OCR Success: ${recognizedText.text.substring(0, minimum(recognizedText.text.length, 100))}...');
        return recognizedText.text;
      } catch (e) {
        debugPrint('OCR Error: $e');
        return "Error extracting text";
      }
    }
    return "Simulated Receipt Text: \nMerchant: Local Store\nDate: 2024-01-01\nTotal: 25.00 EUR\nItems:\n1x Appless - 5.00\n2x Banana - 10.00";
  }

  int minimum(int a, int b) => (a < b) ? a : b;

  /// Streaming token generation — runs LLM in a separate isolate and
  /// streams individual tokens back via a ReceivePort.
  Stream<String> generate(String prompt) async* {
    if (!_isModelLoaded || _modelPath == null) {
      yield "Error: Model not loaded";
      return;
    }

    final receivePort = ReceivePort();
    final modelPath = _modelPath!;

    // Spawn an isolate that sends tokens one by one via SendPort.
    await Isolate.spawn(
      _streamLlamaInIsolate,
      _StreamRequest(modelPath: modelPath, prompt: prompt, sendPort: receivePort.sendPort),
    );

    // Yield tokens as they arrive; the isolate sends null when done.
    await for (final message in receivePort) {
      if (message == null) break;
      yield message as String;
    }

    receivePort.close();
  }

  /// Top-level isolate entrypoint for streaming generation.
  /// Sends each token individually via [sendPort], then sends null to signal
  /// completion, matching the `Stream<String>` contract of [generate].
  static void _streamLlamaInIsolate(_StreamRequest request) {
    final llama = Llama(request.modelPath);
    try {
      llama.setPrompt(request.prompt);

      while (true) {
        final (token, done) = llama.getNext();
        request.sendPort.send(token);
        if (done) break;
      }
    } catch (e) {
      request.sendPort.send("Error: $e");
    } finally {
      llama.dispose();
      request.sendPort.send(null); // Signal completion
    }
  }

  void unload() {
    // Model is only loaded on-demand inside isolates now,
    // so there's nothing to dispose on the main isolate.
    _modelPath = null;
    _isModelLoaded = false;
  }
}

/// Message class for passing data to the streaming isolate.
/// All fields are simple types that can cross the isolate boundary.
class _StreamRequest {
  final String modelPath;
  final String prompt;
  final SendPort sendPort;

  const _StreamRequest({
    required this.modelPath,
    required this.prompt,
    required this.sendPort,
  });
}
