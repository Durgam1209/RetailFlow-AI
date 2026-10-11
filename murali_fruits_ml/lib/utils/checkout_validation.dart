/// Validation helpers shared by checkout forms and unit tests.
bool isValidItemName(String value) {
  final name = value.trim();
  return name.isNotEmpty && name.length <= 60;
}

bool isValidUnitPrice(double? value) =>
    value != null && value.isFinite && value > 0 && value <= 100000;

bool isValidCheckoutQuantity(double? value) =>
    value != null && value.isFinite && value >= 0 && value <= 500;
