/// Group thousands while keeping the requested number of decimal places.
String formatNumber(num value, {int decimals = 0}) {
  final parts = value.toStringAsFixed(decimals).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return parts.length == 1 ? whole : '$whole.${parts[1]}';
}

String formatMoney(num value) => '₱${formatNumber(value, decimals: 2)}';
