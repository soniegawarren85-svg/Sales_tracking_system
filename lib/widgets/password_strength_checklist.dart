import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/password_policy.dart';
import '../theme/app_colors.dart';

class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = PasswordStrength(password);
    final Color color;
    final Color background;
    final String label;
    if (password.isEmpty) {
      color = Colors.blueGrey.shade500;
      background = Colors.blueGrey.shade50;
      label = 'Type a password to check its strength';
    } else if (strength.isStrong) {
      color = Colors.green.shade700;
      background = Colors.green.shade50;
      label = 'Strong password';
    } else if (strength.isAcceptable) {
      color = Colors.amber.shade800;
      background = Colors.amber.shade50;
      label = 'Fair password';
    } else {
      color = Colors.red.shade700;
      background = Colors.red.shade50;
      label = 'Weak password';
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: strength.score / strength.rules.length,
              color: color,
              backgroundColor: Colors.white,
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                password.isEmpty
                    ? Icons.info_outline_rounded
                    : strength.isStrong
                    ? Icons.verified_rounded
                    : strength.isAcceptable
                    ? Icons.shield_outlined
                    : Icons.warning_amber_rounded,
                color: color,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              if (password.isNotEmpty)
                Text(
                  '${strength.score}/${strength.rules.length}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final rule in strength.rules.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    rule.value
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: rule.value ? Colors.green.shade700 : Colors.black38,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule.key,
                      style: TextStyle(
                        color: rule.value
                            ? Colors.black87
                            : Colors.blueGrey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PasswordEntryField extends StatelessWidget {
  const PasswordEntryField({
    super.key,
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.onToggle,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PasswordInputGuard(
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        enabled: enabled,
        autofillHints: null,
        enableInteractiveSelection: false,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
        inputFormatters: const [PasswordTypingFormatter()],
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            onPressed: enabled ? onToggle : null,
            icon: Icon(
              obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AppColors.primaryDark,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordInputGuard extends StatelessWidget {
  const PasswordInputGuard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      final keys = HardwareKeyboard.instance;
      final command = keys.isControlPressed || keys.isMetaPressed;
      if (event is KeyDownEvent &&
          ((command &&
                  [
                    LogicalKeyboardKey.keyC,
                    LogicalKeyboardKey.keyV,
                    LogicalKeyboardKey.keyX,
                  ].contains(event.logicalKey)) ||
              (keys.isShiftPressed &&
                  event.logicalKey == LogicalKeyboardKey.insert))) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}
