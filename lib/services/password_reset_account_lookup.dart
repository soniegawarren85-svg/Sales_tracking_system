import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_validation.dart';
import 'super_admin.dart';

enum PasswordResetAccountStatus {
  ready,
  notFound,
  contactEmailOnly,
  emailChangePending,
  superAdmin,
  unavailable,
}

class PasswordResetAccountLookup {
  const PasswordResetAccountLookup(
    this.status, {
    this.authEmail,
    this.emailChangePending = false,
  });

  final PasswordResetAccountStatus status;
  final String? authEmail;
  final bool emailChangePending;
}

Future<PasswordResetAccountLookup> lookupPasswordResetAccount({
  required FirebaseFirestore firestore,
  required String email,
}) async {
  final normalizedEmail = email.trim().toLowerCase();
  final variants = {email.trim(), normalizedEmail};
  final staffCollection = firestore.collection('staff_requests');
  final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
    for (final field in const ['email', 'authEmail', 'pendingAuthEmail'])
      for (final variant in variants)
        staffCollection.where(field, isEqualTo: variant).get(),
  ];
  final accounts = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final result in await Future.wait(queries)) {
    for (final account in result.docs) {
      accounts[account.id] = account;
    }
  }

  var contactEmailOnly = false;
  var unavailableAccount = false;
  PasswordResetAccountLookup? linkedSuperAdmin;
  for (final account in accounts.values) {
    final data = account.data();
    if (loginAccountStatusError(data) != null ||
        data['isDeleted'] == true ||
        data['isVoided'] == true) {
      unavailableAccount = true;
      continue;
    }
    final profileEmail = data['email']?.toString().trim().toLowerCase() ?? '';
    final authEmail = data['authEmail']?.toString().trim().toLowerCase() ?? '';
    final pendingAuthEmail =
        data['pendingAuthEmail']?.toString().trim().toLowerCase() ?? '';
    if (profileEmail != normalizedEmail &&
        authEmail != normalizedEmail &&
        pendingAuthEmail != normalizedEmail) {
      continue;
    }

    if ((data['role']?.toString().toLowerCase() ?? '') == 'super_admin') {
      final authEmail = data['authEmail']?.toString().trim();
      final authUid = data['authUid']?.toString().trim() ?? '';
      if (authEmail != null &&
          authEmail.isNotEmpty &&
          authEmail.toLowerCase() == normalizedEmail &&
          authUid.isNotEmpty) {
        linkedSuperAdmin = PasswordResetAccountLookup(
          PasswordResetAccountStatus.ready,
          authEmail: authEmail,
        );
      } else {
        linkedSuperAdmin = const PasswordResetAccountLookup(
          PasswordResetAccountStatus.superAdmin,
        );
      }
      continue;
    }

    if (pendingAuthEmail.isNotEmpty &&
        pendingAuthEmail == normalizedEmail &&
        authEmail != pendingAuthEmail) {
      return const PasswordResetAccountLookup(
        PasswordResetAccountStatus.emailChangePending,
        emailChangePending: true,
      );
    }

    final isPendingEmail = pendingAuthEmail == normalizedEmail;
    final signInEmail = isPendingEmail
        ? pendingAuthEmail
        : authEmail.isEmpty
        ? profileEmail
        : authEmail;
    if (signInEmail != normalizedEmail) {
      contactEmailOnly = true;
      continue;
    }

    final status = data['status']?.toString().trim().toLowerCase();
    final unavailable =
        loginAccountStatusError(data) != null ||
        status == 'pending' ||
        status == 'rejected';
    if (unavailable) {
      return const PasswordResetAccountLookup(
        PasswordResetAccountStatus.unavailable,
      );
    }

    return PasswordResetAccountLookup(
      PasswordResetAccountStatus.ready,
      authEmail: signInEmail,
      emailChangePending: isPendingEmail,
    );
  }
  if (linkedSuperAdmin != null) return linkedSuperAdmin;

  final superAdminProfile = await firestore
      .collection('super_admin_profiles')
      .doc(SuperAdmin.id)
      .get();
  final profile = superAdminProfile.data();
  if (profile != null) {
    final authEmail = profile['authEmail']?.toString().trim();
    final profileEmail = profile['email']?.toString().trim();
    final matchesAuthEmail = authEmail?.toLowerCase() == normalizedEmail;
    final authUid = profile['authUid']?.toString().trim() ?? '';
    if (matchesAuthEmail && authUid.isNotEmpty) {
      return PasswordResetAccountLookup(
        PasswordResetAccountStatus.ready,
        authEmail: authEmail,
      );
    }
    if (profileEmail?.toLowerCase() == normalizedEmail ||
        matchesAuthEmail == true) {
      return const PasswordResetAccountLookup(
        PasswordResetAccountStatus.superAdmin,
      );
    }
  }

  return PasswordResetAccountLookup(
    unavailableAccount
        ? PasswordResetAccountStatus.unavailable
        : contactEmailOnly
        ? PasswordResetAccountStatus.contactEmailOnly
        : PasswordResetAccountStatus.notFound,
  );
}
