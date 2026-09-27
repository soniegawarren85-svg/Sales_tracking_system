import 'package:flutter/material.dart';

class StaffDeactivationDialog extends StatefulWidget {
  const StaffDeactivationDialog({super.key, required this.name});
  final String name;
  @override
  State<StaffDeactivationDialog> createState() =>
      _StaffDeactivationDialogState();
}

class _StaffDeactivationDialogState extends State<StaffDeactivationDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Deactivate staff?'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Deactivate ${widget.name}? Enter a reason before confirming.'),
          const SizedBox(height: 16),
          TextField(
            controller: reason,
            onChanged: (_) => setState(() {}),
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, reason.text.trim()),
        child: const Text('Deactivate'),
      ),
    ],
  );
}
