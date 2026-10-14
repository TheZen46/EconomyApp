import '../../features/receipt_scanning/domain/entities/receipt.dart';

/// Service responsible for scrubbing Personally Identifiable Information (PII)
/// from financial transaction data before staging into Tier 1 AI training datasets.
class PiiScrubberService {
  // Regex pattern for emails
  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  // Regex pattern for credit / debit card numbers (13-19 digits, optional dashes/spaces)
  static final RegExp _cardRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  // Regex pattern for phone numbers
  static final RegExp _phoneRegex = RegExp(
    r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}',
  );

  // Regex pattern for IBANs
  static final RegExp _ibanRegex = RegExp(
    r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b',
    caseSensitive: false,
  );

  // Anchored address patterns (number-plus-street structures)
  // Anglo/Germanic style: e.g. "123 Main St.", "42 Broadway Ave", "10 Elm Road", "5 Baker Street"
  static final RegExp _numberStreetRegex = RegExp(
    r"\b\d{1,5}\s+[A-Za-zÀ-ÖØ-öø-ÿ0-9\s.'-]{2,35}\s+(?:Street|St\.|Avenue|Ave\.|Boulevard|Blvd\.|Road|Rd\.|Lane|Ln\.|Drive|Dr\.|Way|Court|Ct\.|Circle|Cir\.|Weg|Strasse|Str\.)\b(?:\s*,?\s*(?:Apt|Suite|Ste|Unit|Floor|Fl|#)?\s*\d+[a-zA-Z]?)?",
    caseSensitive: false,
  );

  // Romance style (prefix + street name + house number): e.g. "Via Roma 42", "Via dei Mille, 45", "Corso Italia 10", "Piazza Garibaldi 3", "Rue de Rivoli 15"
  static final RegExp _prefixStreetRegex = RegExp(
    r"\b(?:Via|Corso|Piazza|Piazzale|Viale|Strada|Largo|Vicolo|Rue|Calle|Avenida)\s+[A-ZÀ-ÖØ-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ0-9\s.'-]{2,35}\s*,?\s*(?:n\.?|no\.?|civ\.?|civico|#)?\s*\d{1,5}[a-zA-Z]?\b",
    caseSensitive: false,
  );

  // Personal name patterns (attendant/customer context labels or honorifics)
  static final RegExp _nameLabelRegex = RegExp(
    r"\b(?:Cashier|Cassiere|Cassiera|Server|Operator|Operatore|Served\s+by|Host|Waiter|Cameriere|Cameriera|Clerk|Associate|Barista|Customer|Client|Cliente|Cardholder|Titolare|Member|Employee|Staff)\s*[:#-]?\s*([A-ZÀ-ÖØ-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ.'-]+(?:\s+[A-ZÀ-ÖØ-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ.'-]+){1,3})\b",
    caseSensitive: false,
  );

  static final RegExp _honorificNameRegex = RegExp(
    r"\b(?:Mr\.?|Mrs\.?|Ms\.?|Miss|Sig\.?|Sig\.ra|Dott\.?|Dott\.ssa|Prof\.?)\s+([A-ZÀ-ÖØ-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ.'-]+(?:\s+[A-ZÀ-ÖØ-öø-ÿ][a-zA-ZÀ-ÖØ-öø-ÿ.'-]+){1,2})\b",
    caseSensitive: false,
  );

  /// Strips all detected PII from an arbitrary text string.
  static String sanitizeText(String? input) {
    if (input == null || input.trim().isEmpty) return '';

    String cleaned = input;

    // 1. Redact Emails
    cleaned = cleaned.replaceAll(_emailRegex, '[REDACTED_EMAIL]');

    // 2. Redact IBAN
    cleaned = cleaned.replaceAll(_ibanRegex, '[REDACTED_IBAN]');

    // 3. Redact Credit Cards (verify card length heuristics)
    cleaned = cleaned.replaceAllMapped(_cardRegex, (match) {
      final digits = match.group(0)?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (digits.length >= 13 && digits.length <= 19) {
        return '[REDACTED_CARD]';
      }
      return match.group(0)!;
    });

    // 4. Redact Phone Numbers
    cleaned = cleaned.replaceAllMapped(_phoneRegex, (match) {
      final digits = match.group(0)?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (digits.length >= 7 && digits.length <= 15) {
        return '[REDACTED_PHONE]';
      }
      return match.group(0)!;
    });

    // 5. Redact Personal Names
    cleaned = cleaned.replaceAllMapped(_nameLabelRegex, (match) {
      final fullMatch = match.group(0)!;
      final name = match.group(1)!;
      final prefix = fullMatch.substring(0, fullMatch.indexOf(name));
      return '$prefix[REDACTED_NAME]';
    });
    cleaned = cleaned.replaceAllMapped(_honorificNameRegex, (match) {
      return '[REDACTED_NAME]';
    });

    // 6. Redact Addresses (anchored to number-street structures)
    cleaned = cleaned.replaceAll(_numberStreetRegex, '[REDACTED_ADDRESS]');
    cleaned = cleaned.replaceAll(_prefixStreetRegex, '[REDACTED_ADDRESS]');

    return cleaned.trim();
  }

  /// Sanitizes a full receipt entity into an anonymized dataset record.
  static Map<String, dynamic> sanitizeReceiptForTraining(Receipt receipt) {
    return {
      'receipt_id': receipt.id,
      'anonymized_merchant': sanitizeText(receipt.merchantName),
      'currency': receipt.currency,
      'scanned_date': receipt.date.toIso8601String(),
      'items': receipt.items.map((item) => sanitizeItemForTraining(
        merchantName: receipt.merchantName,
        item: item,
      )).toList(),
    };
  }

  /// Sanitizes a single receipt line item for the Tier 1 AI training corpus.
  static Map<String, dynamic> sanitizeItemForTraining({
    required String merchantName,
    required ReceiptItem item,
    bool isUserCorrected = false,
  }) {
    return {
      'anonymized_merchant': sanitizeText(merchantName),
      'anonymized_description': sanitizeText(item.description),
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'total_price': item.totalPrice,
      'main_category': item.mainCategory,
      'sub_category': item.subCategory,
      'necessity': item.necessity.name,
      'was_user_corrected': isUserCorrected,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
