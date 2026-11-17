String publicBranchCode(String id) {
  var value = 0;
  for (final unit in id.codeUnits) {
    value = (value * 31 + unit) % 10000000000;
  }
  final digits = value.toString().padLeft(10, '0');
  return 'BR-${digits.substring(0, 5)}-${digits.substring(5, 9)}-${digits.substring(9)}';
}
