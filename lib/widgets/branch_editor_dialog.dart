import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BranchEditorDialog extends StatefulWidget {
  const BranchEditorDialog({super.key, this.initial = const {}});
  final Map<String, dynamic> initial;
  @override
  State<BranchEditorDialog> createState() => _BranchEditorDialogState();
}

class _BranchEditorDialogState extends State<BranchEditorDialog> {
  late final name = TextEditingController(
    text: '${widget.initial['name'] ?? ''}',
  );
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    title: Text(
      widget.initial.isEmpty ? 'Create Branch' : 'Edit Branch',
      style: const TextStyle(color: AppColors.primaryDeep),
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Branch name'),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
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
        style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDeep),
        onPressed: () {
          if (name.text.trim().isEmpty) {
            setState(() => error = 'Enter a branch name.');
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            'name': name.text.trim(),
            'openingMinutes': 0,
            'closingMinutes': 1440,
          });
        },
        child: Text(widget.initial.isEmpty ? 'Create' : 'Save'),
      ),
    ],
  );
}
