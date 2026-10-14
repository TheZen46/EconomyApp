import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/services/ai_service.dart';
import '../../domain/entities/receipt.dart';
import '../../../../core/constants/taxonomy_constants.dart';
import '../../../../core/constants/app_constants.dart';

/// OCR-based fallback for receipt data extraction, used when no AI backend is
/// available.
///
/// Runs on-device Latin ML Kit OCR on Android and iOS and applies regular
/// expression heuristics to the recognized text. When OCR is unavailable (desktop,
/// web) or yields nothing usable, it returns [ExtractionUnavailableFailure]
/// rather than data that was not read from the image.
class FallbackAIService implements AIService {
  @override
  Future<Either<Failure, Receipt>> extractReceiptData(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  }) async {
    try {
      // 1. Attempt OCR if running on Android or iOS and file exists
      String ocrText = '';
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final file = File(imagePath);
          if (await file.exists()) {
            final inputImage = InputImage.fromFilePath(imagePath);
            final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
            final recognizedText = await textRecognizer.processImage(inputImage);
            await textRecognizer.close();
            ocrText = recognizedText.text.trim();
          }
        } catch (e) {
          debugPrint('FallbackAIService: ML Kit OCR skipped/failed: $e');
        }
      }

      // If OCR text was acquired, extract fields heuristically from text
      if (ocrText.isNotEmpty) {
        final parsed = _parseFromOcrText(ocrText, imagePath);
        if (parsed != null) {
          return Right(parsed);
        }
      }

      return const Left(ExtractionUnavailableFailure());
    } catch (e) {
      debugPrint('FallbackAIService error: $e');
      return const Left(AIProcessingFailure('Failed to parse receipt data'));
    }
  }

  /// Public entry point for parsing extracted OCR text into a structured [Receipt].
  @visibleForTesting
  Receipt? parseOcrText(String text, {String imagePath = ''}) {
    return _parseFromOcrText(text, imagePath);
  }

  Receipt? _parseFromOcrText(String text, String imagePath) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return null;

    // Merchant name from top lines (skip generic receipt noise and date/time lines)
    String merchant = 'Merchant Store';
    final noiseWords = {'receipt', 'tax invoice', 'scontrino', 'fattura', 'welcome', 'terminal'};
    final dateOrNumberOnly = RegExp(r'^\s*[\d/:.\- ]+(?:am|pm)?\s*$', caseSensitive: false);
    for (final line in lines.take(5)) {
      final lower = line.toLowerCase();
      if (dateOrNumberOnly.hasMatch(line)) continue;
      if (noiseWords.any((w) => lower == w || lower.startsWith('$w:'))) continue;
      if (line.length >= 3) {
        merchant = line;
        break;
      }
    }

    // Currency detection (detect prior to dates to inform locale date order)
    String currency = 'EUR';
    if (text.contains('\$') || text.contains('USD')) {
      currency = 'USD';
    } else if (text.contains('£') || text.contains('GBP')) {
      currency = 'GBP';
    } else if (text.contains('CHF')) {
      currency = 'CHF';
    } else if (text.contains('€') || text.contains('EUR')) {
      currency = 'EUR';
    }

    // Date extraction with strict component round-trip validation against overflow
    DateTime date = DateTime.now();
    bool dateFound = false;
    final dateRegex = RegExp(r'\b(20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.](?:20)?\d{2})\b');
    for (final line in lines) {
      final match = dateRegex.firstMatch(line);
      if (match != null) {
        final raw = match.group(1)!;
        final parts = raw.split(RegExp(r'[-/.]'));
        if (parts.length == 3) {
          try {
            int year, month, day;
            if (parts[0].length == 4) {
              year = int.parse(parts[0]);
              month = int.parse(parts[1]);
              day = int.parse(parts[2]);
              if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
                final candidate = DateTime(year, month, day);
                if (candidate.year == year && candidate.month == month && candidate.day == day) {
                  date = candidate;
                  dateFound = true;
                  break;
                }
              }
            } else {
              int p0 = int.parse(parts[0]);
              int p1 = int.parse(parts[1]);
              year = int.parse(parts[2]);
              if (year < 100) year += 2000;

              final candidateOrders = <List<int>>[];
              if (p0 > 12 && p1 <= 12) {
                candidateOrders.add([p1, p0]); // p0 is day, p1 is month -> [month, day]
              } else if (p1 > 12 && p0 <= 12) {
                candidateOrders.add([p0, p1]); // p0 is month, p1 is day -> [month, day]
              } else if (p0 <= 12 && p1 <= 12) {
                // Heuristic: USD uses MM/DD/YYYY, others default to DD/MM/YYYY
                if (currency == 'USD') {
                  candidateOrders.add([p0, p1]);
                  candidateOrders.add([p1, p0]);
                } else {
                  candidateOrders.add([p1, p0]);
                  candidateOrders.add([p0, p1]);
                }
              }

              for (final order in candidateOrders) {
                final m = order[0];
                final d = order[1];
                if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
                  final candidate = DateTime(year, m, d);
                  // Strict component round-trip validation prevents rollover (e.g. Feb 31 -> Mar 2)
                  if (candidate.year == year && candidate.month == m && candidate.day == d) {
                    date = candidate;
                    dateFound = true;
                    break;
                  }
                }
              }
              if (dateFound) break;
            }
          } catch (_) {}
        }
      }
    }

    // Items & Total parsing
    final items = <ReceiptItem>[];
    double detectedTotal = 0.0;
    final totalRegex = RegExp(
      r'(?:TOTAL|TOTALE|AMOUNT|SUM|IMPORTO|DUE|BALANCE|GESAMT|SUMME)\s*[:=]?\s*(?:[\$€£]|EUR|USD|GBP|CHF)?\s*(\d+[.,]\d{2})\s*(?:[\$€£]|EUR|USD|GBP|CHF)?',
      caseSensitive: false,
    );
    final lineItemRegex = RegExp(
      r'^(?:(\d+)\s*(?:[xX*@]|pz|stk)?\s+)?(.+?)\s+(?:[\$€£]|EUR|USD|GBP|CHF)?\s*(\d+[.,]\d{2})\s*(?:[\$€£]|EUR|USD|GBP|CHF)?$',
      caseSensitive: false,
    );

    for (final line in lines) {
      final totalMatch = totalRegex.firstMatch(line);
      if (totalMatch != null) {
        final val = double.tryParse(totalMatch.group(1)!.replaceAll(',', '.'));
        if (val != null && val > detectedTotal) {
          detectedTotal = val;
        }
        continue;
      }

      final itemMatch = lineItemRegex.firstMatch(line);
      if (itemMatch != null) {
        final qty = int.tryParse(itemMatch.group(1) ?? '1') ?? 1;
        final desc = itemMatch.group(2)!.trim();
        final rawPrice = double.tryParse(itemMatch.group(3)!.replaceAll(',', '.')) ?? 0.0;
        if (desc.length > 2 && rawPrice > 0) {
          final unitPrice = qty > 0 ? (rawPrice / qty) : rawPrice;
          final classification = TaxonomyConstants.classifyItem(desc);
          final ItemNecessity necessity;
          switch (classification.necessity) {
            case 'essential':
              necessity = ItemNecessity.essential;
              break;
            case 'discretional':
              necessity = ItemNecessity.discretional;
              break;
            case 'junk':
              necessity = ItemNecessity.junk;
              break;
            default:
              necessity = ItemNecessity.essential;
          }

          final lowerDesc = desc.toLowerCase();
          final isHardware = AppConstants.hardwareKeywords.any((k) => lowerDesc.contains(k));
          final isFurniture = AppConstants.furnitureKeywords.any((k) => lowerDesc.contains(k));
          final isAsset = isHardware || isFurniture;

          items.add(ReceiptItem(
            description: desc,
            unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
            quantity: qty,
            totalPrice: rawPrice,
            necessity: necessity,
            mainCategory: classification.mainCategory,
            subCategory: classification.subCategory,
            isAsset: isAsset,
          ));
        }
      }
    }

    if (items.isEmpty && detectedTotal <= 0) return null;

    final computedTotal = detectedTotal > 0
        ? detectedTotal
        : items.fold(0.0, (sum, i) => sum + i.totalPrice);

    return Receipt(
      id: const Uuid().v4(),
      merchantName: merchant,
      date: date,
      time: '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      totalAmount: double.parse(computedTotal.toStringAsFixed(2)),
      currency: currency,
      dateUncertain: !dateFound,
      items: items.isNotEmpty
          ? items
          : [
              ReceiptItem(
                description: 'Receipt Item',
                unitPrice: computedTotal,
                quantity: 1,
                totalPrice: computedTotal,
                necessity: ItemNecessity.essential,
              )
            ],
      imagePath: imagePath,
    );
  }
}

/// Backward compatibility subclass for [FallbackAIService].
class MockAIService extends FallbackAIService {}
