import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/voice_dictation_engine.dart';

void main() {
  group('VoiceDictationEngine Tests', () {
    final refDate = DateTime(2026, 4, 15);

    test('parses compound dollars and cents with merchant and box accurately', () {
      final parsed = VoiceDictationEngine.parseTranscript(
        'Spent 45 dollars and 50 cents at Olive Garden for lunch with Acme Corp in Consulting box',
        referenceDate: refDate,
      );

      expect(parsed.amount, 45.50);
      expect(parsed.merchant, 'Olive Garden');
      expect(parsed.category, 'Meals & Entertainment');
      expect(parsed.boxName?.toLowerCase(), 'consulting');
      expect(parsed.confidenceScore, greaterThanOrEqualTo(0.80));
    });

    test('parses travel ride with yesterday date correctly', () {
      final parsed = VoiceDictationEngine.parseTranscript(
        'Uber ride for \$28.75 to the airport yesterday box Travel',
        referenceDate: refDate,
      );

      expect(parsed.amount, 28.75);
      expect(parsed.category, 'Travel & Transportation');
      expect(parsed.expenseDate.day, 14); // April 14 (yesterday)
      expect(parsed.boxName?.toLowerCase(), 'travel');
    });

    test('parses high-value equipment purchase and classifies Section 179 category', () {
      final parsed = VoiceDictationEngine.parseTranscript(
        'Bought MacBook Pro for 2499 dollars at Apple Store today in Tech box',
        referenceDate: refDate,
      );

      expect(parsed.amount, 2499.0);
      expect(parsed.merchant, 'Apple Store');
      expect(parsed.category, 'Equipment & Section 179');
      expect(parsed.boxName?.toLowerCase(), 'tech');
    });

    test('handles empty transcript gracefully with zero score', () {
      final parsed = VoiceDictationEngine.parseTranscript('', referenceDate: refDate);
      expect(parsed.amount, 0.0);
      expect(parsed.confidenceScore, 0.0);
      expect(parsed.merchant, 'Unknown Merchant');
    });
  });
}
