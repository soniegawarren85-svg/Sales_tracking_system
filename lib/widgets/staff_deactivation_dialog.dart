import 'package:flutter/material.dart';

class StaffDeactivationDialog extends StatefulWidget {
  const StaffDeactivationDialog({super.key, required this.name});
  final String name;
  @override
  State<StaffDeactivationDialog> createState() =>
      _StaffDeactivationDialogState();
}

class _StaffDeactivationDialogState extends State<StaffDeactivationDialog> {
  String? selectedReason;
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
          DropdownButtonFormField<String>(
            initialValue: selectedReason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items:
                const [
                      'Resigned',
                      'End of contract',
                      'Extended absence',
                      'Policy violation',
                      'Other',
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => selectedReason = value),
          ),
          if (selectedReason == 'Other')
            TextField(
              controller: reason,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Other reason'),
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
        onPressed:
            selectedReason == null ||
                (selectedReason == 'Other' && reason.text.trim().isEmpty)
            ? null
            : () => Navigator.pop(
                context,
                selectedReason == 'Other' ? reason.text.trim() : selectedReason,
              ),
        child: const Text('Deactivate'),
      ),
    ],
  );
}
