import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../constants/taxonomy_constants.dart';

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
  "\\"merchant_name\\"" ws ":" ws string "," ws
  "\\"merchant_address\\"" ws ":" ws string "," ws
  "\\"vat_number\\"" ws ":" ws string "," ws
  "\\"date\\"" ws ":" ws date-string "," ws
  "\\"time\\"" ws ":" ws time-string "," ws
  "\\"currency\\"" ws ":" ws currency-code "," ws
  "\\"items\\"" ws ":" ws "[" ws item-list ws "]" "," ws
  "\\"tax_breakdown\\"" ws ":" ws "[" ws tax-list ws "]" "," ws
  "\\"total_amount\\"" ws ":" ws number "," ws
  "\\"confidence_score\\"" ws ":" ws number ws
"}"

item ::= "{" ws
  "\\"raw_name\\"" ws ":" ws string "," ws
  "\\"normalized_name\\"" ws ":" ws string "," ws
  "\\"main_category\\"" ws ":" ws category-string "," ws
  "\\"sub_category\\"" ws ":" ws string "," ws
  "\\"necessity\\"" ws ":" ws necessity-enum "," ws
  "\\"quantity\\"" ws ":" ws integer "," ws
  "\\"unit_price\\"" ws ":" ws number "," ws
  "\\"total_price\\"" ws ":" ws number "," ws
  "\\"is_asset\\"" ws ":" ws boolean ws
"}"

tax-entry ::= "{" ws
  "\\"rate\\"" ws ":" ws number "," ws
  "\\"tax_amount\\"" ws ":" ws number ws
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
