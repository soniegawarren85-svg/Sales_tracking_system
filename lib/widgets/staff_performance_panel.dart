import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import 'profile_avatar.dart';

class StaffPerformancePanel extends StatefulWidget {
  const StaffPerformancePanel({
    super.key,
    required this.branchId,
    this.firestore,
  });
  final FirebaseFirestore? firestore;
  final String branchId;
  @override
  State<StaffPerformancePanel> createState() => _StaffPerformancePanelState();
}

class _StaffPerformancePanelState extends State<StaffPerformancePanel> {
  String? _selected;
  String _search = '';
  DateTimeRange _range = DateTimeRange(
    start: DateUtils.dateOnly(DateTime.now()),
    end: DateUtils.dateOnly(DateTime.now()),
  );
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  late final _branch = _db
      .collection('branches')
      .doc(widget.branchId)
      .snapshots();
  late final _staff = _db.collection('staff_requests').snapshots();
  late final _sales = _db
      .collection('completed_sales')
      .where('branchId', isEqualTo: widget.branchId)
      .snapshots();
  String _name(Map person) =>
      '${person['firstName'] ?? ''} ${person['lastName'] ?? ''}'.trim();
  String _money(dynamic value) => '₱${reportValue(value).toStringAsFixed(2)}';
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 840,
      height: MediaQuery.sizeOf(context).height * .9,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _branch,
        builder: (context, branch) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _staff,
          builder: (context, staff) {
            if (branch.hasError || staff.hasError)
              return const Center(child: Text('Unable to load branch staff.'));
            if (!branch.hasData || !staff.hasData)
              return const Center(child: CircularProgressIndicator());
            final data = branch.data!.data() ?? {};
            final ids = (data['staffIds'] as List? ?? [])
                .map((id) => '$id')
                .toSet();
            final members = staff.data!.docs.where((doc) {
              final r = doc.data();
              return r['isDeleted'] != true &&
                  ([
                        doc.id,
                        r['uid'],
                        r['userId'],
                        r['staffId'],
                      ].any(ids.contains) ||
                      (r['branchIds'] as List? ?? []).contains(
                        widget.branchId,
                      ));
            }).toList();
            final selected =
                members.where((d) => d.id == _selected).firstOrNull ??
                members.firstOrNull;
            final person = selected?.data() ?? {};
            final identity = [
              selected?.id,
              person['uid'],
              person['userId'],
              person['staffId'],
            ].where((v) => v != null && '$v'.isNotEmpty).toSet();
            return Column(
              children: [
                ListTile(
                  title: const Text(
                    'Branch staff',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${data['name'] ?? 'Branch'} • ${members.length} assigned',
                  ),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selected?.id),
                    initialValue: selected?.id,
                    decoration: const InputDecoration(
                      labelText: 'Select staff',
                      border: OutlineInputBorder(),
                    ),
                    items: members
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(_name(d.data())),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                ),
                if (selected != null)
                  ListTile(
                    leading: ProfileAvatar(data: person),
                    title: Text(_name(person)),
                    subtitle: Text(
                      '${person['staffId'] ?? selected.id} • Cashier',
                    ),
                    trailing: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search performance details',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Filter performance by date range',
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${MaterialLocalizations.of(context).formatShortDate(_range.start)} – ${MaterialLocalizations.of(context).formatShortDate(_range.end)}',
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _sales,
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return const Center(
                          child: Text('Unable to load performance.'),
                        );
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final sales =
                          snapshot.data!.docs
                              .map((d) => {...d.data(), '_id': d.id})
                              .where(
                                (r) =>
                                    validReportSale(r) &&
                                    !reportRefund(r) &&
                                    [
                                      r['staffId'],
                                      r['userId'],
                                      r['cashierId'],
                                    ].any(identity.contains) &&
                                    reportInRange(
                                      r['timestamp'] ?? r['createdAt'],
                                      _range.start,
                                      _range.end.add(const Duration(days: 1)),
                                    ) &&
                                    '${_name(person)} ${person['staffId']} ${r['salesId']} ${r['items']} ${r['paymentMode']} ${r['discountName']} ${r['discountType']}'
                                        .toLowerCase()
                                        .contains(_search),
                              )
                              .toList()
                            ..sort(
                              (a, b) =>
                                  (cashRecordDate(
                                            b['timestamp'] ?? b['createdAt'],
                                          ) ??
                                          _range.start)
                                      .compareTo(
                                        cashRecordDate(
                                              a['timestamp'] ?? a['createdAt'],
                                            ) ??
                                            _range.start,
                                      ),
                            );
                      final total = sales.fold<double>(
                        0,
                        (sum, r) => sum + reportValue(r['total']),
                      );
                      final sold = sales.fold<double>(
                        0,
                        (sum, r) =>
                            sum +
                            (r['items'] as List? ?? [])
                                .whereType<Map>()
                                .fold<double>(
                                  0,
                                  (s, i) => s + reportValue(i['quantity']),
                                ),
                      );
                      return Column(
                        children: [
                          Container(
                            key: const ValueKey('staff-performance-summary'),
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xffffeef2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${sales.length} orders • ${sold.toStringAsFixed(0)} items sold • ${_money(total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: sales.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No orders recorded for this staff in this date range.',
                                    ),
                                  )
                                : ListView.builder(
                                    key: const ValueKey(
                                      'staff-performance-details',
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      0,
                                      18,
                                      18,
                                    ),
                                    itemCount: sales.length,
                                    itemBuilder: (context, index) {
                                      final sale = sales[index];
                                      final at =
                                          cashRecordDate(
                                            sale['timestamp'] ??
                                                sale['createdAt'],
                                          ) ??
                                          _range.start;
                                      final discount = reportValue(
                                        sale['discountAmount'] ??
                                            sale['discount'],
                                      );
                                      final tax = reportValue(
                                        sale['tax'] ??
                                            sale['vatAmount'] ??
                                            sale['taxAmount'] ??
                                            sale['vat'],
                                      );
                                      final taxRate = reportValue(
                                        sale['taxRate'],
                                      );
                                      final isVatRegistered =
                                          '${sale['taxClassification'] ?? ''}'
                                              .trim()
                                              .toLowerCase() ==
                                          'vat';
                                      final vatLabel = taxRate > 0
                                          ? 'VAT (${(taxRate * 100).toStringAsFixed(0)}%)'
                                          : 'VAT';
                                      final cashierName =
                                          (sale['cashierName'] ??
                                                  sale['staffName'])
                                              ?.toString()
                                              .trim();
                                      final cashierId =
                                          (sale['staffPublicId'] ??
                                                  sale['staffId'] ??
                                                  person['staffId'] ??
                                                  selected?.id ??
                                                  sale['cashierId'])
                                              ?.toString()
                                              .trim();
                                      return Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Cashier: ${cashierName?.isNotEmpty == true ? cashierName : _name(person)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'Cashier ID: ${cashierId?.isNotEmpty == true ? cashierId : 'Not recorded'}',
                                              ),
                                              Text(
                                                '${MaterialLocalizations.of(context).formatShortDate(at)} ${TimeOfDay.fromDateTime(at).format(context)} • ${sale['paymentMode'] ?? 'Cash'}',
                                              ),
                                              const Divider(),
                                              for (final item
                                                  in (sale['items'] as List? ??
                                                          [])
                                                      .whereType<Map>())
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 6,
                                                      ),
                                                  child: Text(
                                                    '${item['publicId'] ?? item['itemId'] ?? item['id'] ?? item['coffeeId'] ?? 'ID not recorded'} • ${item['variant'] ?? item['name']}\n${item['quantity']} × ${_money(item['price'] ?? item['unitPrice'])}',
                                                  ),
                                                ),
                                              if (discount > 0)
                                                Text(
                                                  'Discount${(sale['discountName'] ?? sale['discountType']) == null ? '' : ' (${sale['discountName'] ?? sale['discountType']})'}: ${_money(discount)}',
                                                ),
                                              if (tax > 0 ||
                                                  taxRate > 0 ||
                                                  isVatRegistered)
                                                Text(
                                                  '$vatLabel: ${_money(tax)}',
                                                ),
                                              Text(
                                                'Total: ${_money(sale['total'])}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
