import 'package:flutter/material.dart';
import '../services/password_policy.dart';
import 'password_strength_checklist.dart';

class ConfirmPasswordDialog extends StatefulWidget {
  const ConfirmPasswordDialog({super.key});

  @override
  State<ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<ConfirmPasswordDialog> {
  final _controller = TextEditingController();
  bool _closing = false;

  void _close([String? password]) {
    if (_closing) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, password);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm your password'),
    content: PasswordInputGuard(
      child: TextField(
        controller: _controller,
        obscureText: true,
        enableInteractiveSelection: false,
        autofillHints: null,
        inputFormatters: const [PasswordTypingFormatter()],
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _close(_controller.text),
        decoration: const InputDecoration(
          labelText: 'Current password',
          prefixIcon: Icon(Icons.lock_outline_rounded),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _close, child: const Text('Cancel')),
      FilledButton(
        onPressed: () => _close(_controller.text),
        child: const Text('Continue'),
      ),
    ],
  );
}
