/// Older inventory replacements stored their value separately from the total.
/// Normalize for receipts and analytics without changing cash drawer movements.
Map<String, dynamic> refundValueRecord(Map<String, dynamic> record) {
  if (record['refundMethod'] != 'inventory') return record;
  double number(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;
  var amount = number(record['total']).abs();
  if (amount == 0) amount = number(record['replacementValue']).abs();
  if (amount == 0) {
    amount = (record['items'] as List? ?? []).whereType<Map>().fold<double>(
      0,
      (sum, item) =>
          sum + number(item['quantity']).abs() * number(item['price']),
    );
  }
  return {
    ...record,
    'total': -amount,
    'subtotal': -amount,
    'cashDrawerDelta': 0.0,
  };
}

String? refundQuantityError(String text, int available) {
  final quantity = int.tryParse(text);
  if (quantity == null || quantity < 1)
    return 'Enter a whole quantity of at least 1.';
  if (quantity > available)
    return 'Only $available sold item(s) are available for refund.';
  return null;
}
