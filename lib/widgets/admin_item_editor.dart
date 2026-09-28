import 'package:sales_tracking/theme/app_colors.dart';
import '../services/short_id_service.dart';
import '../services/bundle_stock_service.dart';
import '../services/bundle_metadata_service.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'admin_catalog.dart';

String inventorySaveError(Object error) {
  if (error is StateError) return error.message;
  if (error is ArgumentError) return '${error.message}';
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Saving was blocked by database permissions. Your administrator needs to check access rules.';
      case 'unauthenticated':
        return 'Your session expired. Sign in again, then save.';
      case 'resource-exhausted':
        return 'The inventory record is too large or the database quota was reached. Try a smaller bundle batch.';
      case 'invalid-argument':
        return 'The record contains unsupported data or is too large. ${error.message ?? ''}';
      case 'aborted':
        return 'Stock changed while saving. Refresh the inventory and retry.';
      case 'unavailable':
        return 'The database is temporarily unavailable. Please retry.';
      default:
        return 'Unable to save (${error.code}): ${error.message ?? 'Please retry.'}';
    }
  }
  return 'Unable to save: $error';
}

Future<void> showAdminItemEditor(
  BuildContext context, {
  AdminCatalogEntry? entry,
  Map<String, dynamic>? category,
  FirebaseFirestore? firestore,
  required Future<String?> Function(Uint8List bytes) upload,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ItemEditor(
    entry: entry,
    category: category,
    upload: upload,
    firestore: firestore,
  ),
);

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    this.entry,
    this.category,
    required this.upload,
    this.firestore,
  });
  final FirebaseFirestore? firestore;
  final AdminCatalogEntry? entry;
  final Map<String, dynamic>? category;
  final Future<String?> Function(Uint8List bytes) upload;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  final _form = GlobalKey<FormState>();
  final _additionalBundles = TextEditingController(text: '0');
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
          TextEditingController(
            text:
                '${(num.tryParse('${_data['basePrice']}') ?? 0) + (num.tryParse('${size['priceDelta']}') ?? 0)}',
          ),
        ),
      )
      .toList();
  bool _saving = false;
  String? _error;
  Uint8List? _photo;
  Future<String?>? _upload;
  String get _type => widget.entry?.type ?? 'Categories';
  List<Map<String, dynamic>> _ingredientOptions = [];
  late List<Map<String, dynamic>> _ingredients = bundleRows(
    widget.entry?.source['items'],
  );
  bool _loadingIngredients = false;
  bool _recipeChanged = false;
  @override
  void initState() {
    super.initState();
    if (_type == 'Bundle') _loadIngredients();
  }

  String _ingredientKey(Map item) =>
      '${item['sourceInventoryId']}::${item['variantId']}';
  Future<void> _loadIngredients() async {
    setState(() => _loadingIngredients = true);
    try {
      final docs = await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('sales_inventory')
          .get();
      final options = <Map<String, dynamic>>[];
      for (final doc in docs.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true || data['isBundle'] == true) continue;
        for (final item in bundleRows(data['items'])) {
          if (!catalogItemActive(item, DateTime.now())) continue;
          options.add({
            ...item,
            'sourceInventoryId': doc.id,
            'variantId': item['id'] ?? item['publicId'] ?? item['name'],
            'parentName': data['name'],
          });
        }
      }
      final coffees = await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('coffee_products')
          .get();
      for (final doc in coffees.docs) {
        options.addAll(bundleBeverageSizes(doc.id, doc.data()));
      }
      if (!mounted) return;
      setState(() {
        _ingredientOptions = options;
        _ingredients = _ingredients.map((item) {
          final exact = options
              .where((option) => _ingredientKey(option) == _ingredientKey(item))
              .toList();
          final byName = options
              .where(
                (option) =>
                    '${option['name']}'.trim().toLowerCase() ==
                    '${item['name']}'.trim().toLowerCase(),
              )
              .toList();
          final match = exact.length == 1
              ? exact.single
              : byName.length == 1
              ? byName.single
              : null;
          return match == null
              ? item
              : {...match, 'quantity': item['quantity'] ?? 1};
        }).toList();
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              'Unable to load current ingredients. Reopen the editor to retry.',
        );
      debugPrint('Load bundle ingredients: $error');
    } finally {
      if (mounted) setState(() => _loadingIngredients = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _price,
      _stock,
      _expiry,
      _description,
      _additionalBundles,
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
      final url = _photo == null
          ? null
          : await (_upload ?? widget.upload(_photo!));
      if (_photo != null && (url == null || url.isEmpty))
        throw StateError('Image upload failed');
      final changes = <String, dynamic>{
        'name': _name.text.trim(),
        _type == 'Beverages' ? 'basePrice' : 'price': _type == 'Beverages'
            ? 0
            : num.parse(_price.text.trim()),
        if (url != null) 'imageUrl': url,
        if (_type == 'Categories') ...{
          'stock': int.parse(_stock.text),
          'expirationDate': _expiry.text,
          if (widget.entry == null) 'startingStock': int.parse(_stock.text),
        },
        if (_type == 'Beverages') ...{
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
      final db = widget.firestore ?? FirebaseFirestore.instance;
      final source = widget.entry?.source ?? widget.category!;
      final ref = db
          .collection(
            _type == 'Beverages' ? 'coffee_products' : 'sales_inventory',
          )
          .doc('${source['id']}');
      final publicId = widget.entry == null
          ? await ShortIdService.next(categoryPrefix('${source['name'] ?? ''}'))
          : null;
      if (_type == 'Bundle' && int.parse(_additionalBundles.text) > 0) {
        if (_loadingIngredients)
          throw StateError('Wait for ingredients to finish loading.');
        if (_ingredients.any(
          (item) => !_ingredientOptions.any(
            (option) => _ingredientKey(option) == _ingredientKey(item),
          ),
        )) {
          throw StateError(
            'Choose an available inventory item for every bundle ingredient.',
          );
        }
        await BundleStockService(db).restock(
          ref.id,
          int.parse(_additionalBundles.text),
          changes,
          ingredients: _ingredients,
        );
        if (mounted) Navigator.pop(context);
        return;
      }
      if (_type == 'Bundle') {
        await updateBundleMetadata(db, ref.id, {
          ...changes,
          if (_recipeChanged) 'items': _ingredients,
        });
        if (mounted) Navigator.pop(context);
        return;
      }
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
            'publicId': publicId,
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
    } catch (error) {
      debugPrint('Inventory save failed: $error');
      _upload = null;
      if (mounted) setState(() => _error = inventorySaveError(error));
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
        const Icon(Icons.image_outlined, color: AppColors.primary);
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.entry == null ? 'Add item' : 'Edit ${widget.entry!.name}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'Name'),
                if (_type != 'Beverages')
                  _field(_price, 'Price (₱)', number: true),
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
                if (_type == 'Beverages') ...[
                  const SizedBox(height: 12),
                  ..._sizes.map(
                    (size) => Row(
                      children: [
                        Expanded(child: _field(size.$1, 'Size')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _field(size.$2, 'Price (₱)', number: true),
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
                              maxWidth: 800,
                              maxHeight: 800,
                              imageQuality: 70,
                            );
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            if (mounted)
                              setState(() {
                                _photo = bytes;
                                _upload = widget
                                    .upload(bytes)
                                    .catchError((_) => null);
                              });
                          },
                  ),
                ),
                if (_type == 'Bundle') ...[
                  _field(
                    _additionalBundles,
                    'Additional bundles (0–100)',
                    number: true,
                    integer: true,
                  ),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bundle items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingIngredients) const LinearProgressIndicator(),
                  ..._ingredients.asMap().entries.map((row) {
                    final item = row.value;
                    final exists = _ingredientOptions.any(
                      (option) =>
                          _ingredientKey(option) == _ingredientKey(item),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              '${row.key}-${_ingredientKey(item)}-${_ingredientOptions.length}',
                            ),
                            initialValue: exists ? _ingredientKey(item) : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Item ${row.key + 1}',
                              helperText: exists
                                  ? 'Expires: ${item['expirationDate'] ?? 'Not recorded'}'
                                  : 'Select the replacement for ${item['name']}',
                              border: const OutlineInputBorder(),
                            ),
                            items: _ingredientOptions
                                .where(
                                  (option) =>
                                      _ingredientKey(option) ==
                                          _ingredientKey(item) ||
                                      !_ingredients.any(
                                        (selected) =>
                                            _ingredientKey(selected) ==
                                            _ingredientKey(option),
                                      ),
                                )
                                .map(
                                  (option) => DropdownMenuItem(
                                    value: _ingredientKey(option),
                                    child: Text(
                                      '${option['name']} (${option['publicId'] ?? option['variantId'] ?? ''})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (key) {
                                    _recipeChanged = true;
                                    if (key != null)
                                      setState(
                                        () => _ingredients[row.key] = {
                                          ..._ingredientOptions.firstWhere(
                                            (option) =>
                                                _ingredientKey(option) == key,
                                          ),
                                          'quantity': item['quantity'] ?? 1,
                                        },
                                      );
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: ValueKey('quantity-${row.key}'),
                            initialValue: '${item['quantity'] ?? 1}',
                            enabled: !_saving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity per bundle',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.numbers),
                            ),
                            validator: (value) =>
                                (int.tryParse(value ?? '') ?? 0) <= 0
                                ? 'Enter a quantity greater than zero'
                                : null,
                            onChanged: (value) {
                              _recipeChanged = true;
                              final quantity = int.tryParse(value);
                              if (quantity != null)
                                _ingredients[row.key]['quantity'] = quantity;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    );
                  }),
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
