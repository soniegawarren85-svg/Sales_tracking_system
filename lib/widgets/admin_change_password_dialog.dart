import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/account_password_service.dart';
import '../services/password_policy.dart';
import '../services/session_actor.dart';
import '../services/verified_profile_email_change.dart';
import 'password_strength_checklist.dart';

class AdminChangePasswordDialog extends StatefulWidget {
  const AdminChangePasswordDialog({super.key});
  @override
  State<AdminChangePasswordDialog> createState() =>
      _AdminChangePasswordDialogState();
}

class _AdminChangePasswordDialogState extends State<AdminChangePasswordDialog> {
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  bool saving = false;
  String? error;
  bool obscureCurrent = true;
  bool obscureNext = true;
  bool obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    next.addListener(_passwordChanged);
  }

  void _passwordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    next.removeListener(_passwordChanged);
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (current.text.isEmpty || next.text.isEmpty || confirm.text.isEmpty) {
      setState(() => error = 'Please complete all password fields.');
      return;
    }
    if (!PasswordStrength(next.text).isAcceptable) {
      setState(
        () => error =
            'Password is weak. Meet at least 3 of the 5 requirements to use a fair password.',
      );
      return;
    }
    if (next.text == current.text) {
      setState(
        () => error = 'Choose a password different from your current one.',
      );
      return;
    }
    if (next.text != confirm.text) {
      setState(() => error = 'New password and confirmation do not match.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final actor = await resolveSessionActor(db, admin: true);
      final ref = db.collection('staff_requests').doc(actor.id);
      final data =
          (await ref.get(const GetOptions(source: Source.server))).data() ?? {};
      final user = FirebaseAuth.instance.currentUser;
      final linkedAuthUid = '${data['authUid'] ?? actor.id}'.trim();
      if (data['passwordAuthMode'] != 'firestore' &&
          (data['authUid'] != null || user?.uid == actor.id)) {
        if (user?.uid == linkedAuthUid && user?.email != null) {
          await user!.reauthenticateWithCredential(
            EmailAuthProvider.credential(
              email: user.email!,
              password: current.text,
            ),
          );
          await user.updatePassword(next.text);
        } else {
          await updateLinkedProfileAuthPassword(
            profileData: data,
            expectedUid: linkedAuthUid,
            currentPassword: current.text,
            newPassword: next.text,
          );
        }
        await ref.update({
          'credentialsChangedAt': FieldValue.serverTimestamp(),
          'passwordAuthMode': 'firebase',
          'passwordCredential': FieldValue.delete(),
          for (final field in legacyPasswordFields) field: FieldValue.delete(),
        });
      } else {
        await changeFirestoreAccountPassword(
          account: ref,
          currentPassword: current.text,
          newPassword: next.text,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      for (final key
          in prefs
              .getKeys()
              .where(
                (key) =>
                    key.startsWith('offlineAccount.') ||
                    key.startsWith('offlineLogin.'),
              )
              .toList()) {
        await prefs.remove(key);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is StateError ? e.message : 'Unable to update password: $e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .82;
    return PopScope(
      canPop: !saving,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: Color(0xFF9D174D),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                PasswordEntryField(
                  controller: current,
                  label: 'Current Password',
                  obscureText: obscureCurrent,
                  onToggle: () =>
                      setState(() => obscureCurrent = !obscureCurrent),
                  enabled: !saving,
                ),
                const SizedBox(height: 12),
                PasswordEntryField(
                  controller: next,
                  label: 'New Password',
                  obscureText: obscureNext,
                  onToggle: () => setState(() => obscureNext = !obscureNext),
                  enabled: !saving,
                ),
                PasswordStrengthChecklist(password: next.text),
                const SizedBox(height: 12),
                PasswordEntryField(
                  controller: confirm,
                  label: 'Confirm New Password',
                  obscureText: obscureConfirm,
                  onToggle: () =>
                      setState(() => obscureConfirm = !obscureConfirm),
                  enabled: !saving,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving ? null : save,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF9D174D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(saving ? 'Saving…' : 'Save Password'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
