import '../services/public_item_id.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/branch_session.dart';

double saleNumber(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;
List<Map> saleItems(Map sale) =>
    (sale['items'] as List? ?? []).whereType<Map>().toList();
String saleStatus(Map sale) {
  final status = '${sale['status'] ?? ''}'.toLowerCase();
  if (sale['type'] == 'refund' ||
      sale['fullyRefunded'] == true ||
      '${sale['salesId']}'.toLowerCase().startsWith('r-') ||
      status.contains('refund'))
    return 'Refund';
  if (saleItems(sale).any((item) => saleNumber(item['refunded']) > 0))
    return 'Partial refund';
  if (status.contains('reduc') ||
      saleItems(sale).any((item) => saleNumber(item['reducedQuantity']) > 0))
    return 'Reduced';
  return 'Completed';
}

String _money(dynamic value) => '₱${saleNumber(value).toStringAsFixed(2)}';
String _date(BuildContext context, dynamic value) {
  if (value is! Timestamp) return 'Not recorded';
  final date = value.toDate();
  final local = MaterialLocalizations.of(context);
  return '${local.formatMediumDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

class AdminRecentSales extends StatefulWidget {
  const AdminRecentSales({super.key});
  @override
  State<AdminRecentSales> createState() => _AdminRecentSalesState();
}

class _AdminRecentSalesState extends State<AdminRecentSales> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sales;
  Timer? _midnight;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _watchToday();
  }

  void _watchToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    _sales = FirebaseFirestore.instance
        .collection('completed_sales')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .snapshots();
    _midnight = Timer(end.difference(now), () {
      if (mounted)
        setState(() {
          _page = 0;
          _watchToday();
        });
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFF8BBD0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: Color(0xFFE91E63)),
              SizedBox(width: 10),
              Text(
                'Recent Sales',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Today', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sales,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Unable to load recent sales. Please check your connection and try again.',
                  ),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final branch = BranchSession.instance.branchId;
              final docs =
                  snapshot.data!.docs
                      .where(
                        (doc) =>
                            branch == null || doc.data()['branchId'] == branch,
                      )
                      .toList()
                    ..sort(
                      (a, b) => (b.data()['timestamp'] as Timestamp).compareTo(
                        a.data()['timestamp'] as Timestamp,
                      ),
                    );
              if (docs.isEmpty)
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No sales recorded today.'),
                );
              final pages = (docs.length / 10).ceil();
              final page = _page.clamp(0, pages - 1);
              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          columnSpacing: 24,
                          dataRowMinHeight: 60,
                          dataRowMaxHeight: 92,
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFFCE4EC),
                          ),
                          columns:
                              const [
                                    'Receipt ID',
                                    'Items',
                                    'Quantity',
                                    'Total',
                                    'Date & time',
                                    'Status',
                                    'Action',
                                  ]
                                  .map((name) => DataColumn(label: Text(name)))
                                  .toList(),
                          rows: docs.skip(page * 10).take(10).map((doc) {
                            final sale = doc.data();
                            final items = saleItems(sale);
                            return DataRow(
                              cells: [
                                DataCell(
                                  SelectableText(
                                    '${sale['salesId'] ?? doc.id}',
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 190,
                                    child: Text(
                                      items
                                          .map(
                                            (item) =>
                                                '${item['name'] ?? 'Item'}${item['variant'] == null ? '' : ' (${item['variant']})'}',
                                          )
                                          .join(', '),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${items.fold<double>(0, (sum, item) => sum + saleNumber(item['quantity'])).toStringAsFixed(0)}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    _money(sale['total']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(_date(context, sale['timestamp'])),
                                ),
                                DataCell(Text(saleStatus(sale))),
                                DataCell(
                                  IconButton(
                                    tooltip: 'View receipt',
                                    icon: const Icon(Icons.visibility_outlined),
                                    onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => _ReceiptDetails(
                                        id: doc.id,
                                        sale: sale,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${page + 1} / $pages • ${docs.length} receipts'),
                      IconButton(
                        tooltip: 'Previous receipts',
                        onPressed: page > 0
                            ? () => setState(() => _page = page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next receipts',
                        onPressed: page + 1 < pages
                            ? () => setState(() => _page = page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _ReceiptDetails extends StatelessWidget {
  const _ReceiptDetails({required this.id, required this.sale});
  final String id;
  final Map<String, dynamic> sale;
  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value == null || '$value'.isEmpty ? 'Not recorded' : '$value',
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Receipt ${sale['salesId'] ?? id}'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _line('Record ID', id),
            _line('Date & time', _date(context, sale['timestamp'])),
            _line('Status', saleStatus(sale)),
            _ReceiptIdentity(sale: sale),
            const Divider(),
            ...saleItems(sale).map(
              (item) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name'] ?? 'Item'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (item['variant'] != null)
                    _line('Variant', item['variant']),
                  _ReceiptItemId(item: Map<String, dynamic>.from(item)),
                  _line(
                    'Quantity × unit price',
                    '${item['quantity']} × ${_money(item['price'])}',
                  ),
                  _line(
                    'Line total',
                    _money(
                      saleNumber(item['quantity']) * saleNumber(item['price']),
                    ),
                  ),
                  if (saleNumber(item['refunded']) > 0)
                    _line('Refunded quantity', item['refunded']),
                  if (saleNumber(item['reducedQuantity']) > 0)
                    _line('Reduced quantity', item['reducedQuantity']),
                  const Divider(),
                ],
              ),
            ),
            _line('Subtotal', _money(sale['subtotal'])),
            if (saleNumber(sale['discount']) != 0) ...[
              _line('Discount', _money(sale['discount'])),
              _line('Discount type', sale['discountType']),
              _line('Discount ID', sale['discountProofId']),
            ],
            _line('Total', _money(sale['total'])),
            _line('Payment method', sale['paymentMode']),
            if ('${sale['paymentMode']}'.trim().toLowerCase() == 'gcash')
              _line('GCash transaction ID', sale['gcashTransactionId']),
            _line('Amount paid', _money(sale['paidAmount'])),
            _line('Change', _money(sale['change'])),
            if (sale['reason'] != null || sale['refundReason'] != null)
              _line('Refund reason', sale['reason'] ?? sale['refundReason']),
            if (sale['originalSalesId'] != null)
              _line('Original receipt', sale['originalSalesId']),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

String publicBranchCode(String id) {
  var value = 0;
  for (final unit in id.codeUnits) {
    value = (value * 31 + unit) % 10000000000;
  }
  final digits = value.toString().padLeft(10, '0');
  return 'BR-${digits.substring(0, 5)}-${digits.substring(5, 9)}-${digits.substring(9)}';
}

class _ReceiptItemId extends StatefulWidget {
  const _ReceiptItemId({required this.item});
  final Map<String, dynamic> item;
  @override
  State<_ReceiptItemId> createState() => _ReceiptItemIdState();
}

class _ReceiptItemIdState extends State<_ReceiptItemId> {
  late final Future<String?> identifier = resolve();
  Future<String?> resolve() async {
    final item = widget.item;
    final explicit =
        item['variantId'] ??
        item['publicItemId'] ??
        item['bundleId'] ??
        item['coffeeId'];
    if (explicit != null && '$explicit'.isNotEmpty) return '$explicit';
    final raw = '${item['itemId'] ?? item['id'] ?? ''}';
    if (RegExp(r'^(VAR-|COF-|BND-|BUNDLE-)').hasMatch(raw)) return raw;
    final sources = [
      item['sourceInventoryId'],
      item['itemId'],
      item['id'],
    ].where((value) => value != null && '$value'.trim().isNotEmpty);
    final source = sources.firstOrNull;
    if (source == null || '$source'.trim().isEmpty || '$source'.contains('/'))
      return null;
    for (final collection in ['sales_inventory', 'coffee_products']) {
      final data =
          (await FirebaseFirestore.instance
                  .collection(collection)
                  .doc('$source')
                  .get())
              .data();
      if (data == null) continue;
      if (data['bundleId'] != null) return '${data['bundleId']}';
      if (data['coffeeId'] != null) return '${data['coffeeId']}';
      final matches = (data['items'] as List? ?? [])
          .whereType<Map>()
          .where(
            (variant) =>
                variant['id'] == item['itemId'] ||
                variant['name'] == item['variant'],
          )
          .toList();
      if (matches.length == 1) return matches.single['id']?.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: identifier,
    builder: (context, snapshot) =>
        const _ReceiptDetails(id: '', sale: {})._line(
          'Item ID',
          snapshot.connectionState == ConnectionState.waiting
              ? 'Loading...'
              : (snapshot.data == null ? null : publicItemId(snapshot.data!)),
        ),
  );
}

class _ReceiptIdentity extends StatefulWidget {
  const _ReceiptIdentity({required this.sale});
  final Map<String, dynamic> sale;
  @override
  State<_ReceiptIdentity> createState() => _ReceiptIdentityState();
}

class _ReceiptIdentityState extends State<_ReceiptIdentity> {
  late final Future<Map<String, dynamic>> _identity = _load();
  Future<Map<String, dynamic>> _load() async {
    final sale = widget.sale;
    final uid = (sale['userId'] ?? sale['staffId'])?.toString();
    final branchId = sale['branchId']?.toString();
    final result = <String, dynamic>{};
    if (uid != null && uid.isNotEmpty) {
      final staff = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(uid)
          .get();
      final data = staff.data() ?? {};
      final name = ['firstName', 'middleName', 'lastName']
          .map((key) => data[key]?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (name.isNotEmpty) result['name'] = name;
      result['staffId'] = data['staffId'];
    }
    if (branchId != null && branchId.isNotEmpty) {
      final branch = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .get();
      result['branch'] = branch.data()?['name'];
      result['branchCode'] =
          branch.data()?['branchCode'] ?? publicBranchCode(branchId);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _identity,
    builder: (context, snapshot) {
      final resolved = snapshot.data ?? {};
      final sale = widget.sale;
      final details = _ReceiptDetails(id: '', sale: sale);
      return Column(
        children: [
          details._line(
            'Created by',
            sale['staffName'] ??
                sale['userName'] ??
                sale['createdByName'] ??
                resolved['name'] ??
                (snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading?'
                    : null),
          ),
          details._line(
            'Staff ID',
            sale['staffPublicId'] ??
                resolved['staffId'] ??
                (RegExp(r'^STF-').hasMatch('${sale['staffId']}')
                    ? sale['staffId']
                    : null),
          ),

          details._line('Branch', sale['branchName'] ?? resolved['branch']),
          details._line(
            'Branch ID',
            sale['branchCode'] ?? resolved['branchCode'],
          ),
        ],
      );
    },
  );
}
