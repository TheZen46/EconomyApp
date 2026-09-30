import 'package:intl/intl.dart';

/// Structured outcome of on-device natural voice expense dictation.
class DictatedExpense {
  final double amount;
  final String currency;
  final String merchant;
  final String category;
  final String? boxName;
  final String? businessPurpose;
  final DateTime expenseDate;
  final double confidenceScore;
  final List<String> detectedKeywords;

  const DictatedExpense({
    required this.amount,
    this.currency = 'USD',
    required this.merchant,
    required this.category,
    this.boxName,
    this.businessPurpose,
    required this.expenseDate,
    required this.confidenceScore,
    this.detectedKeywords = const [],
  });

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
        'merchant': merchant,
        'category': category,
        'boxName': boxName,
        'businessPurpose': businessPurpose,
        'expenseDate': DateFormat('yyyy-MM-dd').format(expenseDate),
        'confidenceScore': confidenceScore,
        'detectedKeywords': detectedKeywords,
      };
}

/// [UNIQUE] On-Device Voice Expense Dictation & Semantic Grammar Parser.
///
/// Converts conversational raw voice dictation transcripts into strictly validated
/// ledger expense transactions without sending audio or transcripts to any cloud servers.
class VoiceDictationEngine {
  // Known category keywords
  static const Map<String, List<String>> _categoryLexicon = {
    'Meals & Entertainment': ['lunch', 'dinner', 'breakfast', 'coffee', 'starbucks', 'restaurant', 'meal', 'cafe', 'drinks', 'food'],
    'Travel & Transportation': ['uber', 'lyft', 'taxi', 'flight', 'airline', 'delta', 'united', 'hotel', 'airbnb', 'train', 'transit', 'parking', 'toll'],
    'Software & SaaS': ['subscription', 'aws', 'google cloud', 'github', 'jetbrains', 'adobe', 'chatgpt', 'openai', 'figma', 'notion', 'slack'],
    'Office Supplies': ['staples', 'office depot', 'paper', 'printer', 'desk', 'stationery', 'pens'],
    'Equipment & Section 179': ['macbook', 'laptop', 'iphone', 'monitor', 'hardware', 'camera', 'ipad', 'computer', 'apple store'],
    'Professional Services': ['lawyer', 'legal', 'cpa', 'accounting', 'subcontractor', 'consulting'],
    'Advertising & Marketing': ['facebook ads', 'google ads', 'meta ads', 'sponsorship', 'domain', 'godaddy', 'namecheap'],
  };

  /// Parses raw transcribed speech text into a structured DictatedExpense
  static DictatedExpense parseTranscript(String rawTranscript, {DateTime? referenceDate}) {
    final text = rawTranscript.trim();
    final now = referenceDate ?? DateTime.now();

    if (text.isEmpty) {
      return DictatedExpense(
        amount: 0.0,
        merchant: 'Unknown Merchant',
        category: 'Uncategorized',
        expenseDate: now,
        confidenceScore: 0.0,
      );
    }

    final lower = text.toLowerCase();
    final detectedKeywords = <String>[];

    // 1. Amount Extraction
    double extractedAmount = 0.0;

    // Pattern 1: Digits with optional decimals (e.g. "$45.50", "45.50 dollars", "45 dollars and 50 cents")
    final amountPattern1 = RegExp(r'\$?\s*(\d+(?:\.\d{1,2})?)\s*(?:dollars?|usd|\$)?', caseSensitive: false);
    final match1 = amountPattern1.firstMatch(text);

    final compoundPattern = RegExp(
      r'(\d+)\s*(?:dollars?|\$)?\s*(?:and)?\s*(\d{1,2})\s*cents?',
      caseSensitive: false,
    );
    final compoundMatch = compoundPattern.firstMatch(text);

    if (compoundMatch != null) {
      final dollars = double.tryParse(compoundMatch.group(1) ?? '0') ?? 0.0;
      final cents = double.tryParse(compoundMatch.group(2) ?? '0') ?? 0.0;
      extractedAmount = dollars + (cents / 100.0);
    } else if (match1 != null) {
      extractedAmount = double.tryParse(match1.group(1) ?? '0') ?? 0.0;
    }

    // 2. Date Extraction
    DateTime expenseDate = now;
    if (lower.contains('yesterday')) {
      expenseDate = now.subtract(const Duration(days: 1));
      detectedKeywords.add('yesterday');
    } else if (lower.contains('today')) {
      expenseDate = now;
      detectedKeywords.add('today');
    } else if (lower.contains('last week')) {
      expenseDate = now.subtract(const Duration(days: 7));
      detectedKeywords.add('last week');
    }

    // 3. Category Resolution
    String resolvedCategory = 'General Business Expense';
    for (final entry in _categoryLexicon.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) {
          resolvedCategory = entry.key;
          detectedKeywords.add(kw);
          break;
        }
      }
      if (resolvedCategory != 'General Business Expense') break;
    }

    // 4. Box Extraction (e.g. "for Box Consulting", "in Tech box", "box Marketing")
    String? extractedBox;
    final boxPattern = RegExp(r'(?:in|for|into)\s+(?:box\s+)?([a-zA-Z0-9_-]+)\s+box|(?:in|for|box)\s+([a-zA-Z0-9_-]+)\s+box|(?:box)\s+([a-zA-Z0-9_-]+)', caseSensitive: false);
    final boxMatch = boxPattern.firstMatch(text);
    if (boxMatch != null) {
      extractedBox = boxMatch.group(1) ?? boxMatch.group(2) ?? boxMatch.group(3);
    }

    // 5. Merchant Extraction (e.g., "at Starbucks", "from Apple Store", "with Uber")
    String resolvedMerchant = 'Direct Expense';
    final merchantPattern = RegExp(r'(?:at|from|to)\s+([a-zA-Z0-9\s&]+?)(?:\s+(?:for|in|on|with|yesterday|today|box|\$|\d)|$)', caseSensitive: false);
    final merchantMatch = merchantPattern.firstMatch(text);
    if (merchantMatch != null) {
      final candidate = merchantMatch.group(1)?.trim() ?? '';
      if (candidate.isNotEmpty && candidate.length > 1 && !candidate.toLowerCase().startsWith('box')) {
        resolvedMerchant = candidate;
      }
    } else {
      // Fallback: check brand keywords
      for (final brand in ['starbucks', 'uber', 'lyft', 'apple store', 'staples', 'amazon', 'delta', 'github', 'aws']) {
        if (lower.contains(brand)) {
          resolvedMerchant = brand.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
          break;
        }
      }
    }

    // 6. Business Purpose (e.g. "with client Acme Corp", "for lunch with Bob")
    String? businessPurpose;
    final purposePattern = RegExp(r'(?:with|for)\s+([a-zA-Z0-9\s&]+?)(?:\s+(?:in|box|yesterday|today|\$|\d)|$)', caseSensitive: false);
    final purposeMatch = purposePattern.firstMatch(text);
    if (purposeMatch != null) {
      businessPurpose = purposeMatch.group(1)?.trim();
    }

    // 7. Confidence Scoring
    double confidence = 0.20;
    if (extractedAmount > 0) confidence += 0.35;
    if (resolvedMerchant != 'Direct Expense') confidence += 0.20;
    if (resolvedCategory != 'General Business Expense') confidence += 0.15;
    if (extractedBox != null) confidence += 0.10;

    return DictatedExpense(
      amount: extractedAmount,
      currency: 'USD',
      merchant: resolvedMerchant,
      category: resolvedCategory,
      boxName: extractedBox,
      businessPurpose: businessPurpose,
      expenseDate: expenseDate,
      confidenceScore: confidence.clamp(0.0, 1.0),
      detectedKeywords: detectedKeywords,
    );
  }
}

