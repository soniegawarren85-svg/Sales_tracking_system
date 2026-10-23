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
  for (final account in accounts.values) {
    final data = account.data();
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
      return const PasswordResetAccountLookup(
        PasswordResetAccountStatus.superAdmin,
      );
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

  final superAdminProfile = await firestore
      .collection('super_admin_profiles')
      .doc(SuperAdmin.id)
      .get();
  final profile = superAdminProfile.data();
  if (profile != null) {
    final profileEmail = profile['email']?.toString().trim().toLowerCase();
    final authEmail = profile['authEmail']?.toString().trim().toLowerCase();
    if (profileEmail == normalizedEmail || authEmail == normalizedEmail) {
      return const PasswordResetAccountLookup(
        PasswordResetAccountStatus.superAdmin,
      );
    }
  }

  return PasswordResetAccountLookup(
    contactEmailOnly
        ? PasswordResetAccountStatus.contactEmailOnly
        : PasswordResetAccountStatus.notFound,
  );
}
