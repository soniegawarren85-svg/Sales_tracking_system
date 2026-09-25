/// Stable numeric display code for variants created by the short-lived editor
/// that used Firestore auto IDs. Keep stored IDs unchanged for stock references.
String publicItemId(String id) {
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
