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
  late int opening = (widget.initial['openingMinutes'] as num?)?.toInt() ?? 600;
  late int closing =
      (widget.initial['closingMinutes'] as num?)?.toInt() ?? 1140;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  TimeOfDay time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  Future<void> pick(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: time(start ? opening : closing),
    );
    if (selected != null && mounted)
      setState(() {
        final minutes = selected.hour * 60 + selected.minute;
        if (start) {
          opening = minutes;
        } else {
          closing = minutes;
        }
        error = null;
      });
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
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Opening time'),
              trailing: OutlinedButton(
                onPressed: () => pick(true),
                child: Text(time(opening).format(context)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Closing time'),
              trailing: OutlinedButton(
                onPressed: () => pick(false),
                child: Text(time(closing).format(context)),
              ),
            ),
            const Text(
              'Orders after closing still count toward that day’s sales and cash drawer.',
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
          if (name.text.trim().isEmpty || closing <= opening) {
            setState(
              () => error =
                  'Enter a branch name and a closing time after opening.',
            );
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            'name': name.text.trim(),
            'openingMinutes': opening,
            'closingMinutes': closing,
          });
        },
        child: Text(widget.initial.isEmpty ? 'Create' : 'Save'),
      ),
    ],
  );
}
