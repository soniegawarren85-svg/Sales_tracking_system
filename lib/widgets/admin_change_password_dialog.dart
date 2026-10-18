import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/account_password_service.dart';
import '../services/session_actor.dart';

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
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (next.text.length < 6 ||
        next.text != confirm.text ||
        next.text == current.text) {
      setState(
        () => error =
            'Use a different password with at least 6 characters and matching confirmation.',
      );
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
      if (data['passwordAuthMode'] != 'firestore' &&
          user?.uid == actor.id &&
          user?.email != null) {
        await user!.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email!,
            password: current.text,
          ),
        );
        await user.updatePassword(next.text);
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
      if (mounted)
        setState(() {
          error = e is StateError ? e.message : 'Unable to update password: $e';
          saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Change Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in [
              (current, 'Current password'),
              (next, 'New password'),
              (confirm, 'Confirm password'),
            ])
              TextField(
                controller: field.$1,
                obscureText: true,
                enabled: !saving,
                decoration: InputDecoration(labelText: field.$2),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (saving) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
