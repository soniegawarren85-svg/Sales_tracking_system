String? loginInputError(String emailOrAccountId, String password) {
  if (emailOrAccountId.isEmpty && password.isEmpty) {
    return 'Please enter your email and password.';
  }
  if (emailOrAccountId.isNotEmpty && emailOrAccountId.trim().isEmpty ||
      password.isNotEmpty && password.trim().isEmpty) {
    return 'This field cannot be empty.';
  }
  if (emailOrAccountId.trim().isEmpty) {
    return 'Email address is required.';
  }
  if (password.trim().isEmpty) {
    return 'Password is required.';
  }

  final value = emailOrAccountId.trim();
  if (isAccountIdLogin(value)) {
    return null;
  }
  if (!RegExp(r'^[^@\s]+@[^@\s]+(?:\.[^@\s]+)+$').hasMatch(value)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

String? loginAccountStatusError(Map<String, dynamic> account) {
  final status = '${account['status'] ?? ''}'
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ');
  if (status == 'deactivated' || account['isDeactivated'] == true) {
    return 'Your account has been deactivated. Please contact your administrator.';
  }
  if (status == 'suspended' ||
      status == 'temporarily suspended' ||
      status == 'temporary suspended' ||
      account['isSuspended'] == true) {
    return 'Your account is temporarily suspended. Please contact your administrator.';
  }
  if (account['requiresBranchAssignment'] == true &&
      (account['branchIds'] is! List ||
          (account['branchIds'] as List).where((id) => '$id'.trim().isNotEmpty).isEmpty)) {
    return 'Your account has no assigned branch. Please ask the super admin to assign you before logging in.';
  }
  return null;
}

String invalidLoginCredentialsMessage() => 'Invalid email or password.';

bool isAccountIdLogin(String value) => RegExp(
  r'^(STF-\d{3}|ADM-\d{3,4}|SPR-001)$',
  caseSensitive: false,
).hasMatch(value.trim());
