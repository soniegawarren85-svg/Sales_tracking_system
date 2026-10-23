import 'package:flutter/services.dart';

class PasswordStrength {
  PasswordStrength(this.password);
  final String password;
  Map<String, bool> get rules => {
    'At least 8 characters': password.runes.length >= 8,
    'One uppercase letter': RegExp(r'[A-Z]').hasMatch(password),
    'One lowercase letter': RegExp(r'[a-z]').hasMatch(password),
    'One number': RegExp(r'[0-9]').hasMatch(password),
    'One special character': RegExp(r'[^a-zA-Z0-9\s]').hasMatch(password),
  };
  int get score => rules.values.where((met) => met).length;
  bool get isAcceptable => score >= 3;
  bool get isStrong => rules.values.every((met) => met);
}

/// Reject bulk insertions (paste/autofill) while allowing typing and deletion.
class PasswordTypingFormatter extends TextInputFormatter {
  const PasswordTypingFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selected = oldValue.selection.isValid
        ? (oldValue.selection.end - oldValue.selection.start).abs()
        : 0;
    final added = newValue.text.length - (oldValue.text.length - selected);
    return added > 1 ? oldValue : newValue;
  }
}
