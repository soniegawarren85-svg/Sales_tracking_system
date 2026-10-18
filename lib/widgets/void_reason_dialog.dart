import 'package:flutter/material.dart';

Future<String?> showVoidReasonDialog(BuildContext context, String name) =>
    showDialog<String>(
      context: context,
      builder: (_) => _VoidReasonDialog(name: name),
    );

class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog({required this.name});
  final String name;
  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
  static const _reasons = [
    'Damaged item',
    'Expired item',
    'Lost or missing',
    'Incorrect item/entry',
    'Others',
  ];
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _selectedReason;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Void ${widget.name}?'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final reason in _reasons)
                  DropdownMenuItem(value: reason, child: Text(reason)),
              ],
              onChanged: (reason) => setState(() => _selectedReason = reason),
              validator: (value) =>
                  value == null ? 'Please select a reason.' : null,
            ),
            if (_selectedReason == 'Others') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Other reason',
                  hintText: 'Type the reason for voiding this item',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    _selectedReason == 'Others' &&
                        (value == null || value.trim().isEmpty)
                    ? 'Please enter a reason.'
                    : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              _selectedReason == 'Others'
                  ? _reason.text.trim()
                  : _selectedReason,
            );
          }
        },
        child: const Text('Void item'),
      ),
    ],
  );
}
