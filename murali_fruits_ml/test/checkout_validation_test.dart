import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/utils/checkout_validation.dart';

void main() {
  test('item name must be non-empty and at most 60 characters', () {
    expect(isValidItemName('  Apple  '), isTrue);
    expect(isValidItemName('   '), isFalse);
    expect(isValidItemName('a' * 61), isFalse);
  });

  test('price rejects negative, zero, non-finite, and excessive values', () {
    expect(isValidUnitPrice(10), isTrue);
    expect(isValidUnitPrice(-1), isFalse);
    expect(isValidUnitPrice(0), isFalse);
    expect(isValidUnitPrice(double.infinity), isFalse);
    expect(isValidUnitPrice(100001), isFalse);
  });

  test('checkout quantity accepts zero through 500 kg only', () {
    expect(isValidCheckoutQuantity(0), isTrue);
    expect(isValidCheckoutQuantity(500), isTrue);
    expect(isValidCheckoutQuantity(-0.1), isFalse);
    expect(isValidCheckoutQuantity(500.1), isFalse);
    expect(isValidCheckoutQuantity(double.nan), isFalse);
  });
}
