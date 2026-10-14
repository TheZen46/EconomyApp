import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/utils/amount_parser.dart';

void main() {
  test('reads both decimal conventions', () {
    expect(AmountParser.parse('12.50'), 12.5);
    expect(AmountParser.parse('12,50'), 12.5);
    expect(AmountParser.parse('1,234.56'), 1234.56);
    expect(AmountParser.parse('1.234,56'), 1234.56);
    expect(AmountParser.parse('1 234,56'), 1234.56);
    expect(AmountParser.parse('€ 7,9'), 7.9);
    expect(AmountParser.parse('-3,20'), -3.2);
    expect(AmountParser.parse('42'), 42);
  });

  test('a lone separator before three digits groups thousands', () {
    expect(AmountParser.parse('1,234'), 1234);
    expect(AmountParser.parse('1.234'), 1234);
    expect(AmountParser.parse('1.234.567'), 1234567);
  });

  test('rejects text that is not an amount', () {
    expect(AmountParser.parse(''), isNull);
    expect(AmountParser.parse('abc'), isNull);
    expect(AmountParser.parse('12,50abc'), isNull);
    expect(AmountParser.parse('1-2'), isNull);
  });
}
