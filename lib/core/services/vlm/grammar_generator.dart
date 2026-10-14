import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../constants/taxonomy_constants.dart';
import 'receipt_vlm_schema.dart';

/// Utility to generate GBNF (GGML BNF) grammar files dynamically
/// based on the active taxonomy hierarchy and custom user categories.
class GrammarGenerator {
  GrammarGenerator._();

  /// Builds a GBNF grammar string reflecting the provided category names.
  static String buildGrammar({
    List<String>? customCategories,
    Map<String, Map<String, List<TaxonomyItem>>>? hierarchy,
  }) {
    final activeHierarchy = hierarchy ?? TaxonomyConstants.hierarchy;
    final categorySet = <String>{};

    // Add categories from taxonomy constants hierarchy
    categorySet.addAll(activeHierarchy.keys);

    // Add any custom categories from user settings
    if (customCategories != null && customCategories.isNotEmpty) {
      categorySet.addAll(customCategories.where((c) => c.trim().isNotEmpty));
    }

    // Default fallback categories
    if (categorySet.isEmpty) {
      categorySet.addAll([
        'Fresh Produce',
        'Proteins & Dairy',
        'Pantry & Bakery',
        'Frozen Foods',
        'Snacks & Drinks',
        'Household & Living',
        'Personal Care',
        'Miscellaneous',
        'Other',
      ]);
    }

    final categoryChoices = categorySet
        .map((c) => '"${_escapeGbnfString(c)}"')
        .join(' | ');

    return '''root ::= "{" ws
  "\\"${ReceiptVlmSchema.keyMerchantName}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyMerchantAddress}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyVatNumber}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyDate}\\"" ws ":" ws date-string "," ws
  "\\"${ReceiptVlmSchema.keyTime}\\"" ws ":" ws time-string "," ws
  "\\"${ReceiptVlmSchema.keyCurrency}\\"" ws ":" ws currency-code "," ws
  "\\"${ReceiptVlmSchema.keyItems}\\"" ws ":" ws "[" ws item-list ws "]" "," ws
  "\\"${ReceiptVlmSchema.keyTaxBreakdown}\\"" ws ":" ws "[" ws tax-list ws "]" "," ws
  "\\"${ReceiptVlmSchema.keyTotalAmount}\\"" ws ":" ws number "," ws
  "\\"${ReceiptVlmSchema.keyConfidenceScore}\\"" ws ":" ws number ws
"}"

item ::= "{" ws
  "\\"${ReceiptVlmSchema.keyRawName}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyNormalizedName}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyMainCategory}\\"" ws ":" ws category-string "," ws
  "\\"${ReceiptVlmSchema.keySubCategory}\\"" ws ":" ws string "," ws
  "\\"${ReceiptVlmSchema.keyNecessity}\\"" ws ":" ws necessity-enum "," ws
  "\\"${ReceiptVlmSchema.keyQuantity}\\"" ws ":" ws integer "," ws
  "\\"${ReceiptVlmSchema.keyUnitPrice}\\"" ws ":" ws number "," ws
  "\\"${ReceiptVlmSchema.keyTotalPrice}\\"" ws ":" ws number "," ws
  "\\"${ReceiptVlmSchema.keyIsAsset}\\"" ws ":" ws boolean ws
"}"

tax-entry ::= "{" ws
  "\\"${ReceiptVlmSchema.keyTaxRate}\\"" ws ":" ws number "," ws
  "\\"${ReceiptVlmSchema.keyTaxAmount}\\"" ws ":" ws number ws
"}"

necessity-enum ::= "\\"essential\\"" | "\\"discretional\\"" | "\\"junk\\"" | "\\"unknown\\""
category-string ::= category-name
category-name ::= $categoryChoices
currency-code ::= "\\"" [A-Z] [A-Z] [A-Z] "\\""
date-string ::= "\\"" [0-9] [0-9] [0-9] [0-9] "-" [0-9] [0-9] "-" [0-9] [0-9] "\\""
time-string ::= "\\"" [0-9] [0-9] ":" [0-9] [0-9] "\\""
boolean ::= "true" | "false"
string ::= "\\"" ([^"\\\\\\x00-\\x1F] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]))* "\\""
number ::= "-"? [0-9]+ ("." [0-9]+)?
integer ::= [0-9]+
item-list ::= item ("," ws item)* | ""
tax-list ::= tax-entry ("," ws tax-entry)* | ""
ws ::= [ \\t\\n\\r]*
''';
  }

  /// Writes a generated grammar file to the target directory.
  static Future<File> generateAndSave({
    required Directory directory,
    String fileName = 'receipt.gbnf',
    List<String>? customCategories,
    Map<String, Map<String, List<TaxonomyItem>>>? hierarchy,
  }) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final content = buildGrammar(
      customCategories: customCategories,
      hierarchy: hierarchy,
    );

    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, flush: true);
    debugPrint('GrammarGenerator: Saved dynamic grammar to ${file.path}');
    return file;
  }

  static String _escapeGbnfString(String s) {
    return s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
