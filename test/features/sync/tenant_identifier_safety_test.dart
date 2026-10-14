import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/evault/data/models/asset_model.dart';
import 'package:t_aidy/features/invoices/data/models/invoice_model.dart';
import 'package:t_aidy/features/receipt_scanning/data/models/receipt_model.dart';

void main() {
  final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  group('Tenant Identifier Safety & UUID Generation (Issue #24 / TAIDY-M02)', () {
    test('ReceiptModel.fromJson generates unique UUID v4 when id is omitted', () {
      final r1 = ReceiptModel.fromJson({
        'merchant_name': 'Store 1',
        'total_amount': 10.0,
      });
      final r2 = ReceiptModel.fromJson({
        'merchant_name': 'Store 2',
        'total_amount': 20.0,
      });

      expect(uuidRegex.hasMatch(r1.id), isTrue, reason: 'Expected UUID v4 but got ${r1.id}');
      expect(uuidRegex.hasMatch(r2.id), isTrue, reason: 'Expected UUID v4 but got ${r2.id}');
      expect(r1.id, isNot(r2.id));
    });

    test('BoxModel.fromJson generates unique UUID v4 when id is omitted', () {
      final b1 = BoxModel.fromJson({'name': 'Box 1'});
      final b2 = BoxModel.fromJson({'name': 'Box 2'});

      expect(uuidRegex.hasMatch(b1.id), isTrue, reason: 'Expected UUID v4 but got ${b1.id}');
      expect(uuidRegex.hasMatch(b2.id), isTrue, reason: 'Expected UUID v4 but got ${b2.id}');
      expect(b1.id, isNot(b2.id));
    });

    test('AssetModel.fromJson generates unique UUID v4 when id is omitted', () {
      final a1 = AssetModel.fromJson({'name': 'Asset 1'});
      final a2 = AssetModel.fromJson({'name': 'Asset 2'});

      expect(uuidRegex.hasMatch(a1.id), isTrue, reason: 'Expected UUID v4 but got ${a1.id}');
      expect(uuidRegex.hasMatch(a2.id), isTrue, reason: 'Expected UUID v4 but got ${a2.id}');
      expect(a1.id, isNot(a2.id));
    });

    test('InvoiceModel.fromJson generates unique UUID v4 when id is omitted', () {
      final i1 = InvoiceModel.fromJson({'client_name': 'Client 1'});
      final i2 = InvoiceModel.fromJson({'client_name': 'Client 2'});

      expect(uuidRegex.hasMatch(i1.id), isTrue, reason: 'Expected UUID v4 but got ${i1.id}');
      expect(uuidRegex.hasMatch(i2.id), isTrue, reason: 'Expected UUID v4 but got ${i2.id}');
      expect(i1.id, isNot(i2.id));
    });

    test('BoxesNotifier.findById resolves "main" as a local alias to default box', () {
      final notifier = BoxesNotifier();
      final box = notifier.findById('main');
      expect(box, isNotNull);
      expect(box!.name, contains('Main Life'));
    });
  });
}
