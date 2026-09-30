import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/export_service.dart';

void main() {
  group('ExportService Tests', () {
    test('sanitizeCsvCell prepends single quote to formula injection triggers', () {
      // Equals
      expect(ExportService.sanitizeCsvCell('=1+1'), "'=1+1");
      expect(ExportService.sanitizeCsvCell('=cmd|\' /C calc\'!A0'), "'=cmd|' /C calc'!A0");

      // Plus
      expect(ExportService.sanitizeCsvCell('+123'), "'+123");

      // At symbol
      expect(ExportService.sanitizeCsvCell('@SUM(A1:B10)'), "'@SUM(A1:B10)");

      // Tab and carriage return
      expect(ExportService.sanitizeCsvCell('\ttext'), "'\ttext");
      expect(ExportService.sanitizeCsvCell('\rtext'), "'\rtext");

      // Minus followed by formula / text
      expect(ExportService.sanitizeCsvCell('-2+3+cmd|...'), "'-2+3+cmd|...");
    });

    test('sanitizeCsvCell preserves valid numbers and benign text', () {
      // Benign text
      expect(ExportService.sanitizeCsvCell('Apple Store'), 'Apple Store');
      expect(ExportService.sanitizeCsvCell('Consulting fee'), 'Consulting fee');

      // Valid negative numeric strings
      expect(ExportService.sanitizeCsvCell('-45.50'), '-45.50');
      expect(ExportService.sanitizeCsvCell('-100'), '-100');

      // Actual number types
      expect(ExportService.sanitizeCsvCell(123), 123);
      expect(ExportService.sanitizeCsvCell(-99.99), -99.99);
      expect(ExportService.sanitizeCsvCell(0.0), 0.0);

      // Empty string
      expect(ExportService.sanitizeCsvCell(''), '');
    });
  });
}
