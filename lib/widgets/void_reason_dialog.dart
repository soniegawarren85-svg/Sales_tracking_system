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
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
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
        child: TextFormField(
          controller: _reason,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Type the reason for voiding this item',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Please enter a reason.'
              : null,
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
          if (_form.currentState!.validate())
            Navigator.pop(context, _reason.text.trim());
        },
        child: const Text('Void item'),
      ),
    ],
  );
}
