/// Stable numeric display code for variants created by the short-lived editor
/// that used Firestore auto IDs. Keep stored IDs unchanged for stock references.
String publicItemId(String id) {
  final match = RegExp(r'^(STF|ADM|CF|BR|BND)-(0*[0-9]+)$').firstMatch(id);
  if (match != null)
    return match[1]! +
        '-' +
        int.parse(match[2]!).toString().padLeft(match[1] == 'ADM' ? 4 : 3, '0');
  if (!RegExp(r'^VAR-[A-Za-z0-9]{20}$').hasMatch(id)) return id;
  var number = BigInt.zero;
  const alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  for (final char in id.substring(4).split('')) {
    number = number * BigInt.from(62) + BigInt.from(alphabet.indexOf(char));
  }
  final digits = number.toString();
  return 'VAR-$digits';
}
