import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'admin_catalog.dart';

Future<void> showAdminItemEditor(
  BuildContext context, {
  AdminCatalogEntry? entry,
  Map<String, dynamic>? category,
  required Future<String?> Function(Uint8List bytes) upload,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ItemEditor(entry: entry, category: category, upload: upload),
);

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({this.entry, this.category, required this.upload});
  final AdminCatalogEntry? entry;
  final Map<String, dynamic>? category;
  final Future<String?> Function(Uint8List bytes) upload;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _data = widget.entry?.details ?? <String, dynamic>{};
  late final _name = TextEditingController(text: '${_data['name'] ?? ''}');
  late final _price = TextEditingController(
    text: '${_data['basePrice'] ?? _data['price'] ?? ''}',
  );
  late final _stock = TextEditingController(
    text: '${_data['stock'] ?? _data['startingStock'] ?? ''}',
  );
  late final _expiry = TextEditingController(
    text: '${_data['expirationDate'] ?? ''}'.split('T').first,
  );
  late final _description = TextEditingController(
    text: '${_data['description'] ?? ''}',
  );
  late final _sizes = (_data['sizes'] as List? ?? [])
      .whereType<Map>()
      .map(
        (size) => (
          TextEditingController(text: '${size['name'] ?? ''}'),
          TextEditingController(text: '${size['priceDelta'] ?? 0}'),
        ),
      )
      .toList();
  bool _saving = false;
  String? _error;
  Uint8List? _photo;
  String get _type => widget.entry?.type ?? 'Categories';

  @override
  void dispose() {
    for (final controller in [
      _name,
      _price,
      _stock,
      _expiry,
      _description,
      ..._sizes.expand((size) => [size.$1, size.$2]),
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final url = _photo == null ? null : await widget.upload(_photo!);
      if (_photo != null && (url == null || url.isEmpty))
        throw StateError('Image upload failed');
      final changes = <String, dynamic>{
        'name': _name.text.trim(),
        _type == 'Coffee' ? 'basePrice' : 'price': num.parse(
          _price.text.trim(),
        ),
        if (url != null) 'imageUrl': url,
        if (_type == 'Categories') ...{
          'stock': int.parse(_stock.text),
          'expirationDate': _expiry.text,
          if (widget.entry == null) 'startingStock': int.parse(_stock.text),
        },
        if (_type == 'Coffee') ...{
          'description': _description.text.trim(),
          'sizes': _sizes
              .map(
                (size) => {
                  'name': size.$1.text.trim(),
                  'priceDelta': num.parse(size.$2.text),
                },
              )
              .toList(),
        },
      };
      final db = FirebaseFirestore.instance;
      final source = widget.entry?.source ?? widget.category!;
      final ref = db
          .collection(_type == 'Coffee' ? 'coffee_products' : 'sales_inventory')
          .doc('${source['id']}');
      await db.runTransaction((tx) async {
        final snapshot = await tx.get(ref);
        final current = snapshot.data();
        if (current == null || current['isDeleted'] == true)
          throw StateError('This record is no longer active');
        if (_type != 'Categories') {
          tx.update(ref, {
            ...changes,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final items = (current['items'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        if (widget.entry == null) {
          items.add({
            ...changes,
            'id':
                'VAR-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1000000).toString().padLeft(6, '0')}',
            'isDeleted': false,
          });
        } else {
          final index = catalogItemIndex(items, widget.entry!.details);
          if (index < 0 || items[index]['isDeleted'] == true)
            throw StateError('Item no longer available');
          items[index] = {...items[index], ...changes};
        }
        tx.update(ref, {'items': items});
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Unable to save. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool integer = false,
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty))
          return 'Enter $label';
        if (number) {
          final amount = num.tryParse(value ?? '');
          if (amount == null ||
              !amount.isFinite ||
              amount < 0 ||
              (integer && int.tryParse((value ?? '').trim()) == null))
            return 'Enter a valid ${integer ? 'whole number' : 'amount'}';
        }
        return null;
      },
    ),
  );

  Widget _image() {
    final url = '${_data['imageUrl'] ?? ''}';
    Widget fallback() =>
        const Icon(Icons.image_outlined, color: Color(0xFFE91E63));
    if (_photo != null) return Image.memory(_photo!, fit: BoxFit.cover);
    if (url.isEmpty) return fallback();
    try {
      return url.startsWith('data:')
          ? Image.memory(
              base64Decode(url.split(',').last),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            );
    } catch (_) {
      return fallback();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.entry == null ? 'Add item' : 'Edit ${widget.entry!.name}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'Name'),
                _field(
                  _price,
                  _type == 'Coffee' ? 'Base price' : 'Price',
                  number: true,
                ),
                if (_type == 'Categories') ...[
                  _field(_stock, 'Current stock', number: true, integer: true),
                  TextFormField(
                    controller: _expiry,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Expiration date',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => DateTime.tryParse(value ?? '') == null
                        ? 'Choose an expiration date'
                        : null,
                    onTap: _saving
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  DateTime.tryParse(_expiry.text) ??
                                  DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null)
                              _expiry.text = date
                                  .toIso8601String()
                                  .split('T')
                                  .first;
                          },
                  ),
                  const SizedBox(height: 14),
                ],
                if (_type == 'Coffee') ...[
                  _field(_description, 'Description', required: false),
                  const Text('Size price = base price + additional price'),
                  const SizedBox(height: 12),
                  ..._sizes.map(
                    (size) => Row(
                      children: [
                        Expanded(child: _field(size.$1, 'Size')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _field(
                            size.$2,
                            'Additional price',
                            number: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: 52, height: 52, child: _image()),
                  ),
                  title: const Text('Item picture'),
                  trailing: IconButton(
                    tooltip: 'Choose picture',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _saving
                        ? null
                        : () async {
                            final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1200,
                            );
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            if (mounted) setState(() => _photo = bytes);
                          },
                  ),
                ),
                if (_type == 'Bundle') ...[
                  const Divider(),
                  ...catalogBundleContents(widget.entry!.source).map(
                    (item) => ListTile(
                      title: Text('${item['name']}'),
                      subtitle: Text(
                        'Expires: ${item['expirationDate'] ?? 'Not recorded'}',
                      ),
                      trailing: Text('×${item['quantity'] ?? 1}'),
                    ),
                  ),
                ],
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving…'
                : widget.entry == null
                ? 'Add'
                : 'Save',
          ),
        ),
      ],
    ),
  );
}

/// Match IDs first; a legacy name fallback is safe only when it is unique.
int catalogItemIndex(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> target,
) {
  final id = target['id'] ?? target['itemId'] ?? target['variantId'];
  final matches = items
      .asMap()
      .entries
      .where(
        (entry) => id != null
            ? (entry.value['id'] ??
                      entry.value['itemId'] ??
                      entry.value['variantId']) ==
                  id
            : entry.value['name'] == target['name'],
      )
      .toList();
  return matches.length == 1 ? matches.single.key : -1;
}
