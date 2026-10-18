import 'account_username.dart';

bool isSuperAdminCreatedAdmin(Map<String, dynamic> account) {
  final role = '${account['role'] ?? ''}'.trim().toLowerCase();
  return role == 'admin' &&
      (account['createdByRole'] == 'super_admin' ||
          '${account['createdBy'] ?? ''}'.trim().toLowerCase() == 'spr-001' ||
          account['requiresBranchAssignment'] == true);
}

List<T> preferSuperAdminCreatedAdmins<T>(
  Iterable<T> accounts, {
  required Map<String, dynamic> Function(T account) dataOf,
  required String username,
}) {
  final normalizedUsername = normalizeAccountUsername(username);
  final matches = accounts.toList();
  if (normalizedUsername != normalizeAccountUsername('ADM-001')) {
    return matches;
  }
  return matches
      .where((account) => isSuperAdminCreatedAdmin(dataOf(account)))
      .toList();
}
