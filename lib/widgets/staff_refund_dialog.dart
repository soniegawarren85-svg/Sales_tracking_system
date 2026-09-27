import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_database_sync_service.dart';

Future<void> showStaffRefundDialog(BuildContext context, String uid) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffRefundDialog(uid: uid),
    );

class _StaffRefundDialog extends StatefulWidget {
  const _StaffRefundDialog({required this.uid});
  final String uid;
  @override
  State<_StaffRefundDialog> createState() => _StaffRefundDialogState();
}

class _StaffRefundDialogState extends State<_StaffRefundDialog> {
  final _receipt = TextEditingController(),
      _reason = TextEditingController(),
      _qty = TextEditingController(text: '1');
  final _service = LocalDatabaseSyncService();
  List<Map<String, dynamic>> _records = [];
  String _source = 'Categories', _error = '';
  String? _selected;
  bool _loading = true, _saving = false;
  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _kind(Map item) => item['isBundle'] == true
      ? 'Bundle'
      : item['isCoffee'] == true
      ? 'Beverages'
      : 'Categories';
  String _key(Map item) =>
      '${item['sourceInventoryId']}|${item['itemId']}|${item['name']}|${item['variant']}|${item['coffeeSize']}';
  String _label(Map item) => [
    item['name'],
    item['variant'],
    item['coffeeSize'],
  ].where((v) => v != null && '$v'.isNotEmpty).join(' / ');
  bool _refund(Map row) =>
      '${row['type']}'.toLowerCase() == 'refund' ||
      '${row['status']}'.toLowerCase() == 'refund';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _service.getCachedCollection('completed_sales');
    if (mounted)
      setState(() {
        _records = cached.where((r) => r['userId'] == widget.uid).toList();
        _loading = false;
      });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('completed_sales')
          .where('userId', isEqualTo: widget.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      await _service.mergeCompletedSales(
        snapshot.docs.map((d) => {...d.data(), '_localDocId': d.id}),
      );
      final records = await _service.getCachedCollection('completed_sales');
      if (mounted && !_saving)
        setState(
          () => _records = records
              .where((r) => r['userId'] == widget.uid)
              .toList(),
        );
    } catch (_) {
      /* Cached receipts remain usable offline. */
    }
  }

  List<Map<String, dynamic>> _lines() {
    final lines = <Map<String, dynamic>>[];
    for (final sale in _records.where(
      (r) => !_refund(r) && r['fullyRefunded'] != true,
    )) {
      final items = (sale['items'] as List? ?? []).whereType<Map>().toList();
      for (var i = 0; i < items.length; i++) {
        final item = Map<String, dynamic>.from(items[i]);
        var refunded = 0;
        for (final refund in _records.where(_refund)) {
          if (refund['source'] == 'Receipt ${sale['salesId']}') {
            refunded = _num(item['quantity']).toInt();
            break;
          }
          if (refund['originalSalesId'] != sale['salesId']) continue;
          for (final returned
              in (refund['items'] as List? ?? []).whereType<Map>()) {
            if (returned['originalItemIndex'] == i)
              refunded += _num(returned['quantity']).toInt();
          }
        }
        final available = _num(item['quantity']).toInt() - refunded;
        if (available <= 0) continue;
        final subtotal = _num(sale['subtotal']);
        final ratio = subtotal > 0 ? _num(sale['total']) / subtotal : 1.0;
        lines.add({
          'sale': sale,
          'item': item,
          'index': i,
          'available': available,
          'unit': _num(item['price']) * ratio,
        });
      }
    }
    return lines;
  }

  Future<void> _save(List<Map<String, dynamic>> lines, bool byReceipt) async {
    if (_saving) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a refund reason.');
      return;
    }
    final requested = byReceipt
        ? lines.fold<int>(0, (sum, l) => sum + (l['available'] as int))
        : int.tryParse(_qty.text) ?? 0;
    final available = lines.fold<int>(
      0,
      (sum, l) => sum + (l['available'] as int),
    );
    if (requested <= 0 || requested > available) {
      setState(() => _error = 'Enter quantity from 1 to $available.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      var remaining = requested;
      for (final line in lines) {
        if (remaining == 0) break;
        final count = remaining < (line['available'] as int)
            ? remaining
            : line['available'] as int;
        final sale = line['sale'] as Map<String, dynamic>;
        final item = line['item'] as Map<String, dynamic>;
        final amount = (line['unit'] as double) * count;
        final id =
            'R-${DateTime.now().microsecondsSinceEpoch}-${line['index']}';
        final cash = '${sale['paymentMode']}'.toLowerCase() != 'gcash';
        await _service.recordCompletedSale({
          'salesId': id,
          'userId': widget.uid,
          'branchId': sale['branchId'],
          'originalSalesId': sale['salesId'],
          'source': 'Receipt item',
          'type': 'refund',
          'status': 'Refund',
          'reason': _reason.text.trim(),
          'subtotal': -amount,
          'total': -amount,
          'discount': 0.0,
          'discountType': 'None',
          'paidAmount': 0.0,
          'change': 0.0,
          'paymentMode': cash ? 'Cash' : 'GCash',
          'cashDrawerDelta': cash ? -amount : 0.0,
          'timestamp': DateTime.now(),
          'items': [
            {
              ...item,
              'quantity': count,
              'price': line['unit'],
              'originalItemIndex': line['index'],
            },
          ],
        });
        remaining -= count;
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Refund saved. Pending records sync when internet returns.',
            ),
          ),
        );
      }
    } catch (e) {
      final saved = await _service.getCachedCollection('completed_sales');
      if (mounted)
        setState(() {
          _records = saved.where((row) => row['userId'] == widget.uid).toList();
          _error = 'Unable to save refund: $e';
          _saving = false;
        });
    }
  }

  @override
  void dispose() {
    _receipt.dispose();
    _reason.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byReceipt = _receipt.text.trim().isNotEmpty;
    final all = _lines();
    final choices = <String, Map<String, dynamic>>{};
    for (final line in all.where((l) => _kind(l['item'] as Map) == _source)) {
      choices[_key(line['item'] as Map)] = line['item'] as Map<String, dynamic>;
    }
    if (!choices.containsKey(_selected)) _selected = null;
    final lines = all
        .where(
          (l) => byReceipt
              ? (l['sale'] as Map)['salesId'].toString().toLowerCase() ==
                    _receipt.text.trim().toLowerCase()
              : _selected != null && _key(l['item'] as Map) == _selected,
        )
        .toList();
    return AlertDialog(
      title: const Text('Refund'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _receipt,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search receipt ID',
                  hintText: 'Paste receipt ID to fill items and quantities',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (!byReceipt) ...[
                DropdownButtonFormField<String>(
                  value: _source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  items: ['Categories', 'Bundle', 'Beverages']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _source = v!;
                          _selected = null;
                        }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Item / beverage size',
                  ),
                  items: choices.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            _label(e.value),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _selected = v),
                ),
                TextField(
                  controller: _qty,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ],
              ...lines.map(
                (line) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_label(line['item'] as Map)),
                  subtitle: Text(
                    'Refundable quantity: ${line['available']} • ₱${(line['unit'] as double).toStringAsFixed(2)} each after discount',
                  ),
                ),
              ),
              if (byReceipt && lines.isEmpty)
                const Text(
                  'Receipt not found in saved records, or all its items have been refunded.',
                ),
              TextField(
                controller: _reason,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              if (_error.isNotEmpty)
                Text(_error, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || lines.isEmpty
              ? null
              : () => _save(lines, byReceipt),
          child: Text(_saving ? 'Saving...' : 'Confirm refund'),
        ),
      ],
    );
  }
}
