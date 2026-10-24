double receiptTaxAmount(Map<String, dynamic> sale) =>
    double.tryParse(
      '${sale['tax'] ?? sale['vatAmount'] ?? sale['taxAmount'] ?? sale['vat'] ?? 0}',
    ) ??
    0;

double receiptVatableSales(Map<String, dynamic> sale) {
  final total = double.tryParse('${sale['total'] ?? 0}') ?? 0;
  final recordedVatableSales = double.tryParse('${sale['vatableSales'] ?? ''}');
  final rate = double.tryParse('${sale['taxRate'] ?? 0}') ?? 0;
  final tax = receiptTaxAmount(sale);
  if (recordedVatableSales != null && (rate > 0 || tax > 0)) {
    return recordedVatableSales;
  }
  return tax == 0 ? total : total - tax;
}

String receiptTaxLabel(Map<String, dynamic> sale) {
  final classification = '${sale['taxClassification'] ?? ''}'
      .toLowerCase()
      .replaceAll('-', '_');
  if (classification == 'vat' || receiptTaxAmount(sale) > 0) return 'VAT';
  if (classification.contains('exempt')) return 'VAT exempt';
  if (classification == 'non_vat' ||
      classification == 'nonvat' ||
      sale.containsKey('tax') ||
      sale.containsKey('vatAmount')) {
    return 'Non-VAT';
  }
  return 'Not recorded';
}
