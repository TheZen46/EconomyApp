import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/cross_border_vat_engine.dart';

void main() {
  group('CrossBorderVatEngine Tests', () {
    test('applies standard domestic VAT when seller and customer are in same country (Germany)', () {
      final result = CrossBorderVatEngine.evaluateTransaction(
        baseAmount: 1000.0,
        sellerCountryCode: 'DE',
        customerCountryCode: 'DE',
        isCustomerBusiness: true,
        customerVatId: 'DE123456789',
      );

      expect(result.treatment, VatTreatment.domesticStandard);
      expect(result.applicableVatRate, 0.19);
      expect(result.calculatedVatAmount, 190.0);
      expect(result.grossTotal, 1190.0);
      expect(result.isValidVatId, true);
    });

    test('applies EU Intra-Community B2B Reverse Charge when valid EU VAT ID is supplied', () {
      // German freelancer invoicing French business with valid French VAT ID
      final result = CrossBorderVatEngine.evaluateTransaction(
        baseAmount: 5000.0,
        sellerCountryCode: 'DE',
        customerCountryCode: 'FR',
        isCustomerBusiness: true,
        customerVatId: 'FRXX123456789',
      );

      expect(result.treatment, VatTreatment.euB2bReverseCharge);
      expect(result.applicableVatRate, 0.0);
      expect(result.calculatedVatAmount, 0.0);
      expect(result.grossTotal, 5000.0);
      expect(result.isValidVatId, true);
      expect(result.statutoryInvoiceNote, contains('Article 196'));
    });

    test('applies destination country VAT under OSS for EU B2C sales (Spain consumer)', () {
      // German freelancer selling digital product to Spanish consumer
      final result = CrossBorderVatEngine.evaluateTransaction(
        baseAmount: 200.0,
        sellerCountryCode: 'DE',
        customerCountryCode: 'ES',
        isCustomerBusiness: false,
      );

      expect(result.treatment, VatTreatment.euB2cOss);
      expect(result.applicableVatRate, 0.21); // Spanish VAT 21%
      expect(result.calculatedVatAmount, 42.0);
      expect(result.grossTotal, 242.0);
      expect(result.statutoryInvoiceNote, contains('OSS'));
    });

    test('zero-rates non-EU export of services (e.g. US client)', () {
      final result = CrossBorderVatEngine.evaluateTransaction(
        baseAmount: 3000.0,
        sellerCountryCode: 'DE',
        customerCountryCode: 'US',
        isCustomerBusiness: true,
      );

      expect(result.treatment, VatTreatment.exportNonEu);
      expect(result.applicableVatRate, 0.0);
      expect(result.calculatedVatAmount, 0.0);
      expect(result.grossTotal, 3000.0);
      expect(result.statutoryInvoiceNote, contains('export of services outside the European Union'));
    });
  });
}
