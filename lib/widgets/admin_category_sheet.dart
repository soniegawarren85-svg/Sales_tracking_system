import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showAdminCategorySheet(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function(String name) save,
}) async {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<Map<String, dynamic>>(
    builder: (_) => AdminCategorySheet(save: save),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
  );
  final result = await navigator.push(route);
  // The pop result arrives before the reverse animation removes the sheet.
  await route.completed;
  return result;
}

class AdminCategorySheet extends StatefulWidget {
  const AdminCategorySheet({super.key, required this.save});
  final Future<Map<String, dynamic>> Function(String name) save;
  @override
  State<AdminCategorySheet> createState() => _AdminCategorySheetState();
}

class _AdminCategorySheetState extends State<AdminCategorySheet> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final category = await widget.save(name);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, category);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Unable to save category. Please try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .45,
        child: ListView(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add Categories',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Create a category, then add its first item.'),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_saving,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Category name',
                hintText: 'e.g. Cakes',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.category_outlined),
              label: Text(_saving ? 'Saving...' : 'Save category'),
            ),
          ],
        ),
      ),
    ),
  );
}
