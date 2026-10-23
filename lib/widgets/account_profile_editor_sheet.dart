import 'package:flutter/material.dart';

import '../services/password_policy.dart';
import '../services/profile_field_validation.dart';
import '../services/profile_email.dart';
import '../theme/app_colors.dart';
import 'password_strength_checklist.dart';

class AccountProfileValues {
  const AccountProfileValues({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.age,
    required this.address,
    required this.currentPassword,
    required this.emailChanged,
    required this.verifyPendingEmail,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String age;
  final String address;
  final String currentPassword;
  final bool emailChanged;
  final bool verifyPendingEmail;
}

class AccountProfileEditorSheet extends StatefulWidget {
  const AccountProfileEditorSheet({
    super.key,
    required this.profile,
    required this.readOnly,
    required this.onSave,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;
  final Future<String> Function(AccountProfileValues values) onSave;

  @override
  State<AccountProfileEditorSheet> createState() =>
      _AccountProfileEditorSheetState();
}

class _AccountProfileEditorSheetState extends State<AccountProfileEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _age;
  late final TextEditingController _address;
  final _currentPassword = TextEditingController();
  late final String _initialEmail;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _verifyPendingEmail = false;
  String? _error;

  bool get _emailChanged =>
      normalizedProfileEmail(_email.text) !=
      normalizedProfileEmail(_initialEmail);

  @override
  void initState() {
    super.initState();
    _initialEmail =
        '${widget.profile['pendingAuthEmail'] ?? widget.profile['email'] ?? widget.profile['authEmail'] ?? ''}'
            .trim();
    _firstName = TextEditingController(
      text: widget.profile['firstName']?.toString() ?? '',
    );
    _middleName = TextEditingController(
      text: widget.profile['middleName']?.toString() ?? '',
    );
    _lastName = TextEditingController(
      text: widget.profile['lastName']?.toString() ?? '',
    );
    _email = TextEditingController(text: _initialEmail);
    _age = TextEditingController(text: widget.profile['age']?.toString() ?? '');
    _address = TextEditingController(
      text: widget.profile['address']?.toString() ?? '',
    );
    _email.addListener(_emailChangedListener);
  }

  void _emailChangedListener() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.removeListener(_emailChangedListener);
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _email.dispose();
    _age.dispose();
    _address.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if ((_emailChanged || _verifyPendingEmail) &&
        _currentPassword.text.isEmpty) {
      setState(() => _error = 'Enter your current password to change Gmail.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.onSave(
        AccountProfileValues(
          firstName: _firstName.text.trim(),
          middleName: _middleName.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
          age: _age.text.trim(),
          address: _address.text.trim(),
          currentPassword: _currentPassword.text,
          emailChanged: _emailChanged,
          verifyPendingEmail: _verifyPendingEmail,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message
              : 'Unable to save account information. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .88;
    final pendingEmail = '${widget.profile['pendingAuthEmail'] ?? ''}'.trim();

    return Container(
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
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.blush,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.blush.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.readOnly
                              ? 'Your account information'
                              : 'Update your personal information',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (pendingEmail.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.mark_email_unread_rounded,
                        color: Colors.amber.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Gmail verification pending for $pendingEmail. The account email changes after you verify it.',
                          style: TextStyle(
                            color: Colors.brown.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!widget.readOnly)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _verifyPendingEmail =
                                      !_verifyPendingEmail,
                                ),
                          child: Text(
                            _verifyPendingEmail ? 'Cancel' : 'Check / resend',
                          ),
                        ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _field(
                        controller: _firstName,
                        label: 'First name',
                        validator: ProfileFieldValidation.name,
                      ),
                      _field(
                        controller: _middleName,
                        label: 'Middle name',
                        validator: (value) =>
                            ProfileFieldValidation.name(value, required: false),
                      ),
                      _field(
                        controller: _lastName,
                        label: 'Last name',
                        validator: (value) =>
                            ProfileFieldValidation.name(value, required: false),
                      ),
                      _field(
                        controller: _email,
                        label: 'Gmail / email',
                        keyboardType: TextInputType.emailAddress,
                        validator: ProfileFieldValidation.gmail,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        child: _emailChanged || _verifyPendingEmail
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PasswordInputGuard(
                                      child: TextFormField(
                                        key: const ValueKey(
                                          'profile-current-password',
                                        ),
                                        controller: _currentPassword,
                                        obscureText: _obscurePassword,
                                        enabled: !widget.readOnly && !_saving,
                                        enableInteractiveSelection: false,
                                        autofillHints: null,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        contextMenuBuilder: (_, _) =>
                                            const SizedBox.shrink(),
                                        inputFormatters: const [
                                          PasswordTypingFormatter(),
                                        ],
                                        decoration: InputDecoration(
                                          labelText: 'Current Password',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline_rounded,
                                          ),
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      'Required to verify that you own this account.',
                                      style: TextStyle(
                                        color: Colors.blueGrey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      _field(
                        controller: _age,
                        label: 'Age',
                        keyboardType: TextInputType.number,
                        validator: ProfileFieldValidation.age,
                      ),
                      _field(
                        controller: _address,
                        label: 'Address',
                        maxLines: 3,
                        validator: ProfileFieldValidation.wordLimit,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(widget.readOnly ? 'Close' : 'Cancel'),
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(_saving ? 'Saving…' : 'Save changes'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: widget.readOnly,
        enabled: !widget.readOnly && !_saving,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.background.withValues(alpha: .38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.blush),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.blush),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}
