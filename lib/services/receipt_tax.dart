double receiptTaxAmount(Map<String, dynamic> sale) =>
    double.tryParse(
      '${sale['tax'] ?? sale['vatAmount'] ?? sale['taxAmount'] ?? sale['vat'] ?? 0}',
    ) ??
    0;

String receiptTaxLabel(Map<String, dynamic> sale) {
  final classification = '${sale['taxClassification'] ?? ''}'
      .toLowerCase()
      .replaceAll('-', '_');
  if (classification == 'vat' || receiptTaxAmount(sale) > 0) return 'VAT';
  if (classification.contains('exempt')) return 'VAT exempt';
  if (classification == 'non_vat' ||
      classification == 'nonvat' ||
      sale.containsKey('tax') ||
      sale.containsKey('vatAmount'))
    return 'Non-VAT';
  return 'Not recorded';
}
