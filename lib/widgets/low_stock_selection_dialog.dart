import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

Future<bool?> showLowStockSelectionDialog({
  required BuildContext context,
  required String title,
  required String description,
  required List<Map<String, dynamic>> items,
  required String submitLabel,
  required String searchHint,
  required Future<void> Function(List<Map<String, dynamic>>) onSubmit,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _LowStockSelectionDialog(
    title: title,
    description: description,
    items: items,
    submitLabel: submitLabel,
    searchHint: searchHint,
    onSubmit: onSubmit,
  ),
);

class _LowStockSelectionDialog extends StatefulWidget {
  const _LowStockSelectionDialog({
    required this.title,
    required this.description,
    required this.items,
    required this.submitLabel,
    required this.searchHint,
    required this.onSubmit,
  });

  final String title;
  final String description;
  final List<Map<String, dynamic>> items;
  final String submitLabel;
  final String searchHint;
  final Future<void> Function(List<Map<String, dynamic>>) onSubmit;

  @override
  State<_LowStockSelectionDialog> createState() =>
      _LowStockSelectionDialogState();
}

class _LowStockSelectionDialogState extends State<_LowStockSelectionDialog> {
  final _searchController = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';
  String? _error;
  bool _saving = false;
  bool _selectAllChecked = false;

  String _key(Map<String, dynamic> item) =>
      '${item['selectionKey'] ?? '${item['type']}|${item['staffInventoryDocId']}|${item['id']}|${item['name']}'}';

  bool _isAlreadyReported(Map<String, dynamic> item) =>
      item['alreadyReported'] == true ||
      (item['alreadyReported'] == null && item['isLowStock'] == true);

  List<Map<String, dynamic>> get _visibleItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items.where((item) {
      final searchable =
          '${item['name'] ?? ''} ${item['type'] ?? ''} ${item['id'] ?? ''}'
              .toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  void _toggleAllVisible(bool selected) {
    setState(() {
      _selectAllChecked =
          selected && _visibleItems.any((item) => !_isAlreadyReported(item));
      for (final item in _visibleItems) {
        if (_isAlreadyReported(item)) continue;
        final key = _key(item);
        if (selected) {
          _selected.add(key);
        } else {
          _selected.remove(key);
        }
      }
    });
  }

  Future<void> _submit() async {
    final selected = widget.items
        .where((item) => _selected.contains(_key(item)))
        .toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Choose at least one item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(selected);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to submit: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.blush,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
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
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _query = value;
                  _selectAllChecked = false;
                }),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
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
                  fillColor: const Color(0xFFFFF7F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _selectAllChecked,
                onChanged: _saving
                    ? null
                    : (value) => _toggleAllVisible(value == true),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Select all',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${_selected.length} selected'),
                activeColor: AppColors.primaryDark,
              ),
              const Divider(height: 1),
              Flexible(
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching items.'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final key = _key(item);
                          final alreadyMarked = _isAlreadyReported(item);
                          final alreadyReported =
                              item['alreadyReported'] == true;
                          final selected = _selected.contains(key);
                          final type = '${item['type'] ?? 'Inventory'}';
                          return CheckboxListTile(
                            value: selected,
                            onChanged: _saving
                                ? null
                                : alreadyMarked
                                ? (_) => setState(
                                    () => _error =
                                        '${item['name'] ?? 'This item'} is ${alreadyReported ? 'already reported' : 'already marked low stock'}.',
                                  )
                                : (value) => setState(() {
                                    if (value == true) {
                                      _selected.add(key);
                                    } else {
                                      _selected.remove(key);
                                    }
                                    _selectAllChecked = false;
                                    _error = null;
                                  }),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.primaryDark,
                            title: Text(
                              '${item['name'] ?? 'Item'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              alreadyMarked
                                  ? alreadyReported
                                        ? 'Already reported'
                                        : 'Already marked low stock'
                                  : '$type${'${item['id'] ?? ''}'.isEmpty ? '' : ' • ID ${item['id']}'}',
                            ),
                          );
                        },
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
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _saving
                      ? 'Submitting...'
                      : '${widget.submitLabel} (${_selected.length})',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
