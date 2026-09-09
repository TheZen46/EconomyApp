import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/grammar_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GrammarGenerator Tests', () {
    test('buildGrammar contains root, item, and category definitions', () {
      final grammar = GrammarGenerator.buildGrammar();

      expect(grammar.contains('root ::='), isTrue);
      expect(grammar.contains(r'\"merchant_name\"'), isTrue);
      expect(grammar.contains(r'\"total_amount\"'), isTrue);
      expect(grammar.contains(r'\"tax_breakdown\"'), isTrue);
      expect(grammar.contains(r'\"necessity\"'), isTrue);
      expect(grammar.contains('Fresh Produce'), isTrue);
      expect(grammar.contains('Proteins & Dairy'), isTrue);
    });

    test('buildGrammar incorporates custom user categories', () {
      final custom = ['Crypto Expense', 'Pet Toys & Accessories'];
      final grammar = GrammarGenerator.buildGrammar(customCategories: custom);

      expect(grammar.contains('"Crypto Expense"'), isTrue);
      expect(grammar.contains('"Pet Toys & Accessories"'), isTrue);
    });

    test('generateAndSave writes grammar file to disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('gbnf_test_');
      try {
        final file = await GrammarGenerator.generateAndSave(
          directory: tempDir,
          fileName: 'test_receipt.gbnf',
          customCategories: ['Hardware Store'],
        );

        expect(await file.exists(), isTrue);
        final content = await file.readAsString();
        expect(content.contains('"Hardware Store"'), isTrue);
        expect(content.contains('date-string ::='), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
