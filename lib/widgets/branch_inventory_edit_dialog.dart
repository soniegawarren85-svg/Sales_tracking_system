import 'package:flutter/material.dart';

typedef BranchInventoryEdit = ({String name, double price, int? stock});

class BranchInventoryEditDialog extends StatefulWidget {
  const BranchInventoryEditDialog({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  State<BranchInventoryEditDialog> createState() =>
      _BranchInventoryEditDialogState();
}

class _BranchInventoryEditDialogState extends State<BranchInventoryEditDialog> {
  final form = GlobalKey<FormState>();
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit branch inventory'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name.'
                  : null,
            ),
            TextFormField(
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
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, (
            name: name.text.trim(),
            price: double.parse(price.text.trim()),
            stock: batchStock ? null : int.parse(stock.text.trim()),
          ));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
