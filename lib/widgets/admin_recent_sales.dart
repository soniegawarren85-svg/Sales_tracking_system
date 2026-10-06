import '../services/refund_value.dart';
import '../services/inventory_display_ids.dart';
import 'package:sales_tracking/theme/app_colors.dart';
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
  const AdminRecentSales({super.key, this.firestore});
  final FirebaseFirestore? firestore;
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
    _sales = (widget.firestore ?? FirebaseFirestore.instance)
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
      side: const BorderSide(color: AppColors.blush),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: AppColors.primary),
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
              final pages = (docs.length / 5).ceil();
              final page = _page.clamp(0, pages - 1);
              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 760
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: docs.skip(page * 5).take(5).map((doc) {
                          final sale = refundValueRecord(doc.data());
                          final items = saleItems(sale);
                          return SizedBox(
                            width: width,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        avatar: const Icon(
                                          Icons.receipt_long,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${sale['salesId'] ?? doc.id}',
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => ReceiptDetails(
                                            id: doc.id,
                                            sale: sale,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 16,
                                        ),
                                        label: const Text('View all details'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _money(sale['total']),
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    items
                                        .map(
                                          (item) =>
                                              '${item['variant'] ?? item['name'] ?? 'Item'}',
                                        )
                                        .join(', '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        '${items.fold<double>(0, (sum, item) => sum + saleNumber(item['quantity'])).toStringAsFixed(0)} items',
                                      ),
                                      Text('${sale['paymentMode'] ?? 'Cash'}'),
                                      Text(
                                        saleStatus(sale),
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Text(
                                    _date(context, sale['timestamp']),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
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

class ReceiptDetails extends StatelessWidget {
  const ReceiptDetails({required this.id, required Map<String, dynamic> sale})
    : _sale = sale;
  final String id;
  final Map<String, dynamic> _sale;
  Map<String, dynamic> get sale => refundValueRecord(_sale);
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
    backgroundColor: AppColors.surface,
    titlePadding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.blush,
            child: Icon(Icons.receipt_long, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Receipt ${sale['salesId'] ?? id}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
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
                    '${item['isBundle'] == true
                        ? 'Bundle'
                        : item['isCoffee'] == true
                        ? 'Beverages'
                        : item['name'] ?? 'Item'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (item['variant'] != null ||
                      item['isBundle'] == true ||
                      item['isCoffee'] == true)
                    _line(
                      'Variant',
                      (item['variant']?.toString().trim().isNotEmpty ?? false)
                          ? item['variant']
                          : item['name'],
                    ),
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
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: AppColors.primaryDeep,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                child: _line('Total', _money(sale['total'])),
              ),
            ),
            _line(
              saleStatus(sale) == 'Refund' ? 'Refund method' : 'Payment method',
              sale['refundMethod'] == 'inventory'
                  ? 'Inventory replacement'
                  : sale['paymentMode'],
            ),
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
    for (final collection in ['sales_inventory', 'coffee_products']) {
      final snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final source = item['sourceInventoryId'] ?? item['productId'];
        final rawId = item['itemId'] ?? item['id'] ?? item['variantId'];
        if ((source == doc.id || rawId == doc.id) &&
            (data['isBundle'] == true || data['items'] == null)) {
          return inventoryDisplayId(data);
        }
        final matches = (data['items'] as List? ?? [])
            .whereType<Map>()
            .where(
              (variant) =>
                  variant['id'] == rawId ||
                  (source == doc.id && variant['name'] == item['variant']),
            )
            .toList();
        if (matches.length == 1)
          return inventoryDisplayId(Map<String, dynamic>.from(matches.single));
      }
    }
    final fallback = inventoryDisplayId(item);
    return fallback == '--' ? null : fallback;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: identifier,
    builder: (context, snapshot) =>
        const ReceiptDetails(id: '', sale: {})._line(
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
      final details = ReceiptDetails(id: '', sale: sale);
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
