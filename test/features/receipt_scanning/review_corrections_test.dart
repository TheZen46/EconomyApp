import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/pages/review_page.dart';

void main() {
  const extracted = ReceiptItem(
    description: 'Latte Macchiato',
    unitPrice: 2.5,
    totalPrice: 2.5,
    mainCategory: 'Food & Drink',
    subCategory: 'Coffee',
  );

  test('an item saved as extracted is not a correction', () {
    expect(isUserCorrection(extracted, extracted), isFalse);
    // Price edits do not change the name or classification.
    expect(isUserCorrection(extracted, extracted.copyWith(unitPrice: 3, totalPrice: 3)), isFalse);
  });

  test('changes to the name or classification are corrections', () {
    expect(isUserCorrection(extracted, extracted.copyWith(description: 'Latte')), isTrue);
    expect(isUserCorrection(extracted, extracted.copyWith(subCategory: 'Tea')), isTrue);
    expect(isUserCorrection(extracted, extracted.copyWith(necessity: ItemNecessity.junk)), isTrue);
  });

  test('items added by the user are not corrections', () {
    expect(isUserCorrection(null, extracted), isFalse);
  });
}
