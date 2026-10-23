import 'package:flutter/material.dart';

typedef BranchInventoryEdit = ({String name, double price, int? stock});

class BranchInventoryEditDialog extends StatefulWidget {
  const BranchInventoryEditDialog({super.key, required this.item, this.onSave});
  final Map<String, dynamic> item;
  final Future<void> Function(BranchInventoryEdit value)? onSave;
  @override
  State<BranchInventoryEditDialog> createState() =>
      _BranchInventoryEditDialogState();
}

class _BranchInventoryEditDialogState extends State<BranchInventoryEditDialog> {
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final value = (
      name: name.text.trim(),
      price: double.parse(price.text.trim()),
      stock: batchStock ? null : int.parse(stock.text.trim()),
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave?.call(value);
      if (mounted) Navigator.pop(context, value);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e is StateError
              ? e.message
              : 'Unable to save inventory. Please try again.';
        });
    }
  }

  late final name = TextEditingController(text: '${widget.item['name'] ?? ''}');
  late final price = TextEditingController(
    text: '${widget.item['price'] ?? 0}',
  );
  late final stock = TextEditingController(
    text:
        '${(num.tryParse('${widget.item['remaining'] ?? widget.item['stock'] ?? widget.item['bundleCount'] ?? 0}') ?? 0).toInt()}',
  );
  bool get batchStock =>
      widget.item['type'] == 'Bundle' &&
      (widget.item['bundleInstances'] as List? ?? []).isNotEmpty;

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Edit branch inventory'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                enabled: !saving,
                controller: name,
                decoration: const InputDecoration(labelText: 'Item name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an item name.'
                    : null,
              ),
              TextFormField(
                enabled: !saving,
                controller: price,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  return parsed == null || !parsed.isFinite || parsed < 0
                      ? 'Enter a valid non-negative price.'
                      : null;
                },
              ),
              if (!batchStock)
                TextFormField(
                  enabled: !saving,
                  controller: stock,
                  decoration: const InputDecoration(labelText: 'Stock'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed < 0
                        ? 'Enter a whole, non-negative stock amount.'
                        : null;
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Bundle stock is managed by its allocated batches.',
                  ),
                ),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
