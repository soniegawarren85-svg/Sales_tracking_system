import 'package:flutter/material.dart';
import '../services/cash_drawer_service.dart';

typedef BranchInventoryEdit = ({
  String name,
  double price,
  int? stock,
  Map<String, double> sizePrices,
  DateTime? expirationDate,
});

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
  DateTime? selectedExpirationDate;
  bool clearExpirationDate = false;

  bool get beverages => widget.item['type'] == 'Beverages';
  bool get addons => widget.item['type'] == 'Add-ons';

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final value = (
      name: name.text.trim(),
      price: beverages
          ? (num.tryParse('${widget.item['price'] ?? 0}') ?? 0).toDouble()
          : double.parse(price.text.trim()),
      stock: batchStock || beverages || addons
          ? null
          : int.parse(stock.text.trim()),
      sizePrices: {
        for (final entry in sizePriceControllers)
          entry.$1: double.parse(entry.$2.text.trim()),
      },
      expirationDate: clearExpirationDate
          ? null
          : selectedExpirationDate ??
                CashDrawerService.toDate(widget.item['expirationDate']),
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
  late final sizePriceControllers = (widget.item['sizes'] as List? ?? [])
      .whereType<Map>()
      .map((size) {
        final sizeName = '${size['name'] ?? ''}'.trim();
        final overrides = widget.item['branchSizePriceOverrides'] as Map? ?? {};
        final priceOverride = num.tryParse('${overrides[sizeName] ?? ''}');
        final base = num.tryParse('${widget.item['basePrice'] ?? 0}') ?? 0;
        final price =
            priceOverride ??
            base +
                (num.tryParse('${size['priceDelta'] ?? size['price'] ?? 0}') ??
                    0);
        return (
          sizeName,
          TextEditingController(text: price.toStringAsFixed(2)),
        );
      })
      .toList();
  bool get batchStock =>
      widget.item['type'] == 'Bundle' &&
      (widget.item['bundleInstances'] as List? ?? []).isNotEmpty;

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    stock.dispose();
    for (final entry in sizePriceControllers) {
      entry.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseExpirationDate() async {
    final initial =
        selectedExpirationDate ??
        CashDrawerService.toDate(widget.item['expirationDate']) ??
        DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) {
      setState(() {
        selectedExpirationDate = value;
        clearExpirationDate = false;
      });
    }
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
              if (beverages) ...[
                for (final entry in sizePriceControllers)
                  TextFormField(
                    enabled: !saving,
                    controller: entry.$2,
                    decoration: InputDecoration(
                      labelText: '${entry.$1} price',
                      prefixText: '₱ ',
                    ),
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
              ] else
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
              if (addons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiration date'),
                  subtitle: Text(
                    clearExpirationDate
                        ? 'Not set'
                        : (selectedExpirationDate ??
                                      CashDrawerService.toDate(
                                        widget.item['expirationDate'],
                                      ))
                                  ?.toLocal()
                                  .toString()
                                  .split(' ')
                                  .first ??
                              'Not set',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Choose expiration date',
                        onPressed: saving ? null : _chooseExpirationDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                      if (!clearExpirationDate &&
                          (selectedExpirationDate != null ||
                              widget.item['expirationDate'] != null))
                        IconButton(
                          tooltip: 'Clear expiration date',
                          onPressed: saving
                              ? null
                              : () => setState(() {
                                  selectedExpirationDate = null;
                                  clearExpirationDate = true;
                                }),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                ),
              if (!batchStock && !beverages && !addons)
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
              else if (batchStock)
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
