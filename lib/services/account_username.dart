bool isValidStaffLoginUsername(String value) =>
    RegExp(r'^STF-\d{3}$').hasMatch(value.trim().toUpperCase());

bool isValidAccountLoginUsername(String value) =>
    RegExp(r'^(STF|ADM)-\d{3}$').hasMatch(value.trim().toUpperCase());

/// Match stored public account IDs regardless of legacy zero padding or case.
String normalizeAccountUsername(String value) {
  final cleaned = value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp('[\u2013\u2014\u2212]'), '-')
      .replaceAll(' ', '');
  final match = RegExp(r'^(ADM|STF)-([0-9O]+)$').firstMatch(cleaned);
  if (match == null) return cleaned;
  final number = int.parse(match[2]!.replaceAll('O', '0'));
  return '${match[1]}-${number.toString().padLeft(match[1] == 'ADM' ? 4 : 3, '0')}';
}

List<String> accountUsernameAliases(String value) {
  final normalized = normalizeAccountUsername(value);
  final match = RegExp(r'^(ADM|STF)-(\d+)$').firstMatch(normalized);
  final aliases = <String>{normalized, normalized.toLowerCase()};
  if (match != null) {
    for (final width in [3, 4]) {
      final alias =
          '${match[1]}-${int.parse(match[2]!).toString().padLeft(width, '0')}';
      aliases.addAll([alias, alias.toLowerCase()]);
    }
  }
  return aliases.toList();
}
