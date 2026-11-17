import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

Future<bool?> showLowStockReminderDialog({
  required BuildContext context,
  required String title,
  required String description,
  required List<Map<String, dynamic>> items,
  required Future<void> Function(List<Map<String, dynamic>>) onRequest,
  bool readOnly = false,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _LowStockReminderDialog(
    title: title,
    description: description,
    items: items,
    onRequest: onRequest,
    readOnly: readOnly,
  ),
);

class _LowStockReminderDialog extends StatefulWidget {
  const _LowStockReminderDialog({
    required this.title,
    required this.description,
    required this.items,
    required this.onRequest,
    required this.readOnly,
  });

  final String title;
  final String description;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(List<Map<String, dynamic>>) onRequest;
  final bool readOnly;

  @override
  State<_LowStockReminderDialog> createState() =>
      _LowStockReminderDialogState();
}

class _LowStockReminderDialogState extends State<_LowStockReminderDialog> {
  final _searchController = TextEditingController();
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _requestQuantityControllers = {};
  String _query = '';
  String _type = 'All';
  String? _error;
  bool _saving = false;

  String _key(Map<String, dynamic> item) =>
      '${item['allocationId'] ?? item['staffInventoryDocId'] ?? ''}|${item['id'] ?? item['name'] ?? ''}|${item['name'] ?? item['id'] ?? ''}|${item['type'] ?? ''}';

  bool _isAlreadyRequested(Map<String, dynamic> item) =>
      item['alreadyRequested'] == true ||
      item['lowStockReportStatus'] == 'reported' ||
      item['lowStockReportStatus'] == 'requested';

  String _dateLabel(BuildContext context, Map<String, dynamic> item) {
    final value =
        item['allocatedAt'] ??
        item['assignedAt'] ??
        item['allocationDate'] ??
        item['createdAt'];
    final date = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse('$value');
    return date == null
        ? '--'
        : MaterialLocalizations.of(context).formatShortDate(date.toLocal());
  }

  String _itemId(Map<String, dynamic> item) =>
      '${item['publicId'] ?? item['itemPublicId'] ?? item['id'] ?? item['itemId'] ?? item['coffeeId'] ?? item['addonId'] ?? '--'}';

  TextEditingController _requestQuantityController(
    Map<String, dynamic> item,
  ) => _requestQuantityControllers.putIfAbsent(
    _key(item),
    TextEditingController.new,
  );

  bool _hasPhysicalStock(Map<String, dynamic> item) =>
      ['Categories', 'Category', 'Bundle'].contains('${item['type'] ?? ''}');

  Widget _columnHeader(String label, double width) => SizedBox(
    width: width,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  List<Map<String, dynamic>> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return widget.items.where((item) {
      final type = '${item['type'] ?? 'Categories'}';
      final matchesType = _type == 'All' || type == _type;
      final searchable =
          '${item['name'] ?? ''} ${item['id'] ?? ''} ${item['categoryName'] ?? ''} $type'
              .toLowerCase();
      return matchesType && (query.isEmpty || searchable.contains(query));
    }).toList();
  }

  List<Map<String, dynamic>> get _selectableVisibleItems =>
      _visibleItems.where((item) => !_isAlreadyRequested(item)).toList();

  bool get _allVisibleItemsSelected {
    final selectable = _selectableVisibleItems;
    return selectable.isNotEmpty &&
        selectable.every((item) => _selected.contains(_key(item)));
  }

  bool get _someVisibleItemsSelected =>
      _selectableVisibleItems.any((item) => _selected.contains(_key(item)));

  void _toggleVisibleSelection(bool? selected) {
    setState(() {
      for (final item in _selectableVisibleItems) {
        if (selected == true) {
          _selected.add(_key(item));
        } else {
          _selected.remove(_key(item));
        }
      }
    });
  }

  Future<void> _submit() async {
    final selected = <Map<String, dynamic>>[];
    for (final item in _visibleItems.where(
      (item) => _selected.contains(_key(item)),
    )) {
      final quantityText = _requestQuantityControllers[_key(item)]?.text
          .trim();
      if (_hasPhysicalStock(item) && quantityText?.isNotEmpty == true) {
        final quantity = int.tryParse(quantityText!);
        if (quantity == null || quantity <= 0) {
          setState(
            () => _error =
                'Enter a whole number greater than zero for ${item['name']}.',
          );
          return;
        }
      }
      selected.add({
        ...item,
        if (_hasPhysicalStock(item) && quantityText?.isNotEmpty == true)
          'requestedQuantity': int.parse(quantityText!),
      });
    }
    if (selected.isEmpty) {
      setState(() => _error = 'Choose at least one low-stock item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onRequest(selected);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Low-stock request sent to Super Admin.'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error, stackTrace) {
      debugPrint('Low-stock request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      final message = switch (error) {
        FirebaseException(:final message, :final code) =>
          message?.trim().isNotEmpty == true
              ? message!
              : 'Request failed ($code).',
        StateError(:final message) => message,
        ArgumentError(:final message) =>
          message?.toString() ?? 'Invalid request.',
        _ => error.toString(),
      };
      if (mounted) setState(() => _error = 'Unable to send request: $message');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _requestQuantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: const Color(0xFFFFFBFC),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEF2),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${widget.items.length} low-stock item(s)',
                          style: TextStyle(
                            color: Colors.blueGrey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: TextStyle(color: Colors.blueGrey.shade700, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search low-stock items',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFF0D8DF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFF0D8DF)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final type in const [
                      'All',
                      'Categories',
                      'Bundle',
                      'Beverages',
                      'Add-ons',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(type),
                          selected: _type == type,
                          onSelected: (_) => setState(() => _type = type),
                          selectedColor: AppColors.primaryDark,
                          labelStyle: TextStyle(
                            color: _type == type
                                ? Colors.white
                                : AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No items match this filter.'),
                        ),
                      )
                    : Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: compact ? 1450 : 1500,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: DataTable(
                                showCheckboxColumn: false,
                                horizontalMargin: 12,
                                columnSpacing: 12,
                                headingRowColor: WidgetStateProperty.all(
                                  const Color(0xFFFFF0F3),
                                ),
                                columns: [
                                  if (!widget.readOnly)
                                    DataColumn(
                                      columnWidth: const FixedColumnWidth(120),
                                      label: Tooltip(
                                        message: 'Select all visible items',
                                        child: Checkbox(
                                          tristate: true,
                                          value: _allVisibleItemsSelected
                                              ? true
                                              : _someVisibleItemsSelected
                                              ? null
                                              : false,
                                          onChanged:
                                              _saving ||
                                                  _selectableVisibleItems
                                                      .isEmpty
                                              ? null
                                              : _toggleVisibleSelection,
                                        ),
                                      ),
                                    ),
                                  DataColumn(
                                    columnWidth: const FixedColumnWidth(120),
                                    label: _columnHeader('ID', 96),
                                  ),
                                  DataColumn(
                                    columnWidth: const FixedColumnWidth(240),
                                    label: _columnHeader('Allocated date', 216),
                                  ),
                                  DataColumn(
                                    columnWidth: FixedColumnWidth(224),
                                    label: _columnHeader('Item', 200),
                                  ),
                                  DataColumn(
                                    columnWidth: FixedColumnWidth(180),
                                    label: _columnHeader('Category', 156),
                                  ),
                                  DataColumn(
                                    columnWidth: FixedColumnWidth(90),
                                    label: _columnHeader('Stock', 66),
                                  ),
                                  DataColumn(
                                    columnWidth: const FixedColumnWidth(160),
                                    label: _columnHeader('Request qty', 136),
                                  ),
                                  DataColumn(
                                    columnWidth: FixedColumnWidth(180),
                                    label: _columnHeader('Status', 156),
                                  ),
                                ],
                                rows: [
                                  for (final item in visible)
                                    DataRow(
                                      selected: _selected.contains(_key(item)),
                                      cells: [
                                        if (!widget.readOnly)
                                          DataCell(
                                            Checkbox(
                                              value: _selected.contains(
                                                _key(item),
                                              ),
                                              onChanged:
                                                  _saving ||
                                                      _isAlreadyRequested(item)
                                                  ? null
                                                  : (selected) => setState(() {
                                                      if (selected == true) {
                                                        _selected.add(
                                                          _key(item),
                                                        );
                                                      } else {
                                                        _selected.remove(
                                                          _key(item),
                                                        );
                                                      }
                                                    }),
                                            ),
                                          ),
                                        DataCell(
                                          Text(
                                            _itemId(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _dateLabel(context, item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${item['name'] ?? 'Item'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${item['categoryName'] ?? item['type'] ?? 'Inventory'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${item['stock'] ?? item['remaining'] ?? 0}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 136,
                                            child: _hasPhysicalStock(item)
                                                ? TextField(
                                                    key: ValueKey(
                                                      'low-stock-request-quantity-${_key(item)}',
                                                    ),
                                                    controller:
                                                        _requestQuantityController(
                                                          item,
                                                        ),
                                                    enabled:
                                                        !_saving &&
                                                        !_isAlreadyRequested(
                                                          item,
                                                        ),
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration:
                                                        const InputDecoration(
                                                          isDense: true,
                                                          hintText:
                                                              'Optional',
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                  )
                                                : const Text('Made to order'),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _isAlreadyRequested(item)
                                                ? 'Already requested'
                                                : 'Low stock',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _isAlreadyRequested(item)
                                                  ? Colors.blueGrey
                                                  : Colors.deepOrange,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Later'),
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _saving
                              ? 'Sending...'
                              : 'Request (${_selected.length})',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
