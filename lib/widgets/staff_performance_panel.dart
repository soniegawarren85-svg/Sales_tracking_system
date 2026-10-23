import '../theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/receipt_tax.dart';
import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import 'historical_cash_drawer.dart';
import 'profile_avatar.dart';
import 'activity_feed.dart';
import 'staff_performance_search_header.dart';

bool performanceAccountBelongsToBranch({
  required String branchId,
  required Set<String> branchAccountIds,
  required String documentId,
  required Map<String, dynamic> account,
}) =>
    [
      documentId,
      account['uid'],
      account['userId'],
      account['staffId'],
      account['adminId'],
    ].any((id) => id != null && branchAccountIds.contains('$id')) ||
    (account['branchIds'] as List? ?? []).any((id) => '$id' == branchId);

String performanceAccountRole(Map<String, dynamic> account) {
  final role = '${account['role'] ?? ''}'.trim().toLowerCase();
  if (role.isNotEmpty) return role;

  final adminId = '${account['adminId'] ?? ''}'.trim();
  final username = '${account['username'] ?? ''}'.trim().toUpperCase();
  if (adminId.isNotEmpty || username.startsWith('ADM-')) return 'admin';

  final staffId = '${account['staffId'] ?? ''}'.trim();
  if (staffId.isNotEmpty || username.startsWith('STF-')) return 'staff';
  return '';
}

bool performanceAccountAvailable({
  required String branchId,
  required Set<String> branchAccountIds,
  required String documentId,
  required Map<String, dynamic> account,
  required bool roleSelection,
  required String? selectedRole,
}) {
  final status = '${account['status'] ?? ''}'.trim().toLowerCase();
  if (account['isDeleted'] == true ||
      account['isDeactivated'] == true ||
      account['isSuspended'] == true ||
      status == 'deactivated' ||
      status == 'suspended') {
    return false;
  }
  if (roleSelection &&
      selectedRole != null &&
      performanceAccountRole(account) != selectedRole) {
    return false;
  }

  return performanceAccountBelongsToBranch(
    branchId: branchId,
    branchAccountIds: branchAccountIds,
    documentId: documentId,
    account: account,
  );
}

class _PerformanceSummaryHeader extends SliverPersistentHeaderDelegate {
  const _PerformanceSummaryHeader({required this.child});

  final Widget child;

  @override
  double get minExtent => 58;

  @override
  double get maxExtent => 58;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Colors.white,
    elevation: overlapsContent ? 3 : 0,
    child: SizedBox.expand(child: child),
  );

  @override
  bool shouldRebuild(covariant _PerformanceSummaryHeader oldDelegate) =>
      child != oldDelegate.child;
}

class _PerformanceSummary extends StatelessWidget {
  const _PerformanceSummary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('staff-performance-summary'),
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffffeef2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

class StaffPerformancePanel extends StatefulWidget {
  const StaffPerformancePanel({
    super.key,
    required this.branchId,
    this.firestore,
    this.roleSelection = false,
  });
  final FirebaseFirestore? firestore;
  final String branchId;
  final bool roleSelection;
  @override
  State<StaffPerformancePanel> createState() => _StaffPerformancePanelState();
}

class _StaffPerformancePanelState extends State<StaffPerformancePanel> {
  String? _selected;
  String? _role;
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
      '${person['firstName'] ?? ''} ${person['lastName'] ?? ''}'.trim().isEmpty
      ? '${person['adminId'] ?? person['staffId'] ?? 'Account'}'
      : '${person['firstName'] ?? ''} ${person['lastName'] ?? ''}'.trim();
  String _money(dynamic value) => '₱${reportValue(value).toStringAsFixed(2)}';

  List<Map<String, dynamic>> _matchingSales(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    Set<dynamic> identity,
    Map person,
  ) =>
      snapshot.docs
          .map((doc) => {...doc.data(), '_id': doc.id})
          .where(
            (sale) =>
                validReportSale(sale) &&
                !reportRefund(sale) &&
                [
                  sale['staffId'],
                  sale['userId'],
                  sale['cashierId'],
                ].any(identity.contains) &&
                reportInRange(
                  sale['timestamp'] ?? sale['createdAt'],
                  _range.start,
                  _range.end.add(const Duration(days: 1)),
                ) &&
                '${_name(person)} ${person['staffId']} ${sale['salesId']} ${sale['items']} ${sale['paymentMode']} ${sale['discountName']} ${sale['discountType']}'
                    .toLowerCase()
                    .contains(_search),
          )
          .toList()
        ..sort(
          (a, b) =>
              (cashRecordDate(b['timestamp'] ?? b['createdAt']) ?? _range.start)
                  .compareTo(
                    cashRecordDate(a['timestamp'] ?? a['createdAt']) ??
                        _range.start,
                  ),
        );

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Widget _searchHeader() => SliverPersistentHeader(
    pinned: true,
    delegate: PerformanceSearchHeader(
      search: _search,
      range: _range,
      onSearchChanged: (value) =>
          setState(() => _search = value.trim().toLowerCase()),
      onPickRange: _pickRange,
    ),
  );

  Widget _performanceBody({required Widget child}) => SliverToBoxAdapter(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height * .9 - 90,
      ),
      child: child,
    ),
  );

  Widget _dateHeader(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${MaterialLocalizations.of(context).formatShortDate(_range.start)} – ${MaterialLocalizations.of(context).formatShortDate(_range.end)}',
        textAlign: TextAlign.center,
      ),
    ),
  );

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
            if (branch.hasError || staff.hasError) {
              return const Center(child: Text('Unable to load branch staff.'));
            }
            if (!branch.hasData || !staff.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = branch.data!.data() ?? {};
            final ids = (data['staffIds'] as List? ?? [])
                .map((id) => '$id')
                .toSet();
            final members = staff.data!.docs.where((doc) {
              if (!widget.roleSelection &&
                  performanceAccountRole(doc.data()) != 'staff') {
                return false;
              }
              return performanceAccountAvailable(
                branchId: widget.branchId,
                branchAccountIds: ids,
                documentId: doc.id,
                account: doc.data(),
                roleSelection: widget.roleSelection,
                selectedRole: _role,
              );
            }).toList();
            final selected =
                members.where((d) => d.id == _selected).firstOrNull ??
                (widget.roleSelection ? null : members.firstOrNull);
            final person = selected?.data() ?? {};
            final identity = [
              selected?.id,
              person['uid'],
              person['userId'],
              person['staffId'],
              person['adminId'],
            ].where((v) => v != null && '$v'.isNotEmpty).toSet();
            return Column(
              children: [
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              Container(
                                color: AppColors.primaryDeep,
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    listTileTheme: const ListTileThemeData(
                                      textColor: Colors.white,
                                      iconColor: Colors.white,
                                    ),
                                  ),
                                  child: ListTile(
                                    title: const Text(
                                      'Branch staff',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${data['name'] ?? 'Branch'} • ${members.length} ${_role == 'admin' ? 'admins' : 'accounts'}',
                                    ),
                                    trailing: IconButton(
                                      onPressed: () => Navigator.pop(context),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              if (widget.roleSelection)
                                Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(_role),
                                    initialValue: _role,
                                    decoration: const InputDecoration(
                                      labelText: 'Select role',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'admin',
                                        child: Text('Admin'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'staff',
                                        child: Text('Staff'),
                                      ),
                                    ],
                                    onChanged: (value) => setState(() {
                                      _role = value;
                                      _selected = null;
                                    }),
                                  ),
                                ),
                              if (!widget.roleSelection || _role != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    8,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey('${_role}_${selected?.id}'),
                                    initialValue: selected?.id,
                                    decoration: InputDecoration(
                                      labelText: widget.roleSelection
                                          ? (_role == 'admin'
                                                ? 'Select admin'
                                                : 'Select staff')
                                          : 'Select staff',
                                      hintText: 'Select account',
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: members
                                        .map(
                                          (d) => DropdownMenuItem(
                                            value: d.id,
                                            child: Text(
                                              '${_name(d.data())} • ${d.data()['adminId'] ?? d.data()['staffId'] ?? d.id}',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: members.isEmpty
                                        ? null
                                        : (value) =>
                                              setState(() => _selected = value),
                                  ),
                                ),
                              if (widget.roleSelection &&
                                  _role != null &&
                                  members.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    8,
                                  ),
                                  child: Text(
                                    _role == 'admin'
                                        ? 'No active admin accounts found.'
                                        : 'No staff assigned to this branch.',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              if (selected != null)
                                ListTile(
                                  leading: ProfileAvatar(data: person),
                                  title: Text(_name(person)),
                                  subtitle: Text(
                                    '${person['adminId'] ?? person['staffId'] ?? selected.id} • ${performanceAccountRole(person) == 'admin' ? 'Admin' : 'Staff'}',
                                  ),
                                  trailing: const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.green,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _searchHeader(),
                        if (selected != null &&
                            (!widget.roleSelection ||
                                performanceAccountRole(person) == 'staff'))
                          SliverPersistentHeader(
                            pinned: false,
                            delegate: _PerformanceSummaryHeader(
                              child:
                                  StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: _sales,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasError) {
                                        return const _PerformanceSummary(
                                          text: 'Unable to load performance.',
                                        );
                                      }
                                      if (!snapshot.hasData) {
                                        return const _PerformanceSummary(
                                          text: 'Loading performance summary…',
                                        );
                                      }
                                      final sales = _matchingSales(
                                        snapshot.data!,
                                        identity,
                                        person,
                                      );
                                      final total = sales.fold<double>(
                                        0,
                                        (amount, sale) =>
                                            amount + reportValue(sale['total']),
                                      );
                                      final sold = sales.fold<double>(
                                        0,
                                        (quantity, sale) =>
                                            quantity +
                                            (sale['items'] as List? ?? [])
                                                .whereType<Map>()
                                                .fold<double>(
                                                  0,
                                                  (quantityTotal, item) =>
                                                      quantityTotal +
                                                      reportValue(
                                                        item['quantity'],
                                                      ),
                                                ),
                                      );
                                      return _PerformanceSummary(
                                        text:
                                            '${sales.length} orders • ${sold.toStringAsFixed(0)} items sold • ${_money(total)}',
                                      );
                                    },
                                  ),
                            ),
                          ),
                        _dateHeader(context),
                        if (selected != null &&
                            performanceAccountRole(person) != 'admin')
                          SliverToBoxAdapter(
                            child: ActivityFeed(
                              actorIds: {...identity.map((id) => '$id')},
                              branchId: widget.branchId,
                              includeReceipts: true,
                              search: _search,
                              range: _range,
                              database: _db,
                              cardRows: true,
                            ),
                          ),
                        if (widget.roleSelection && selected == null)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'Select a role and account to view performance.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        else if (widget.roleSelection &&
                            performanceAccountRole(person) == 'admin')
                          _performanceBody(
                            child: ActivityFeed(
                              actorIds: {
                                selected!.id,
                                ...identity.map((id) => '$id'),
                              },
                              branchId: widget.branchId,
                              includeReceipts: true,
                              search: _search,
                              range: _range,
                              database: _db,
                              cardRows: true,
                            ),
                          )
                        else
                          _performanceBody(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _sales,
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return const Center(
                                    child: Text('Unable to load performance.'),
                                  );
                                }

                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final sales = _matchingSales(
                                  snapshot.data!,
                                  identity,
                                  person,
                                );
                                return Column(
                                  children: [
                                    if (sales.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'No orders recorded for this staff in this date range.',
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    else
                                      ListView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
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
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                      in (sale['items']
                                                                  as List? ??
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
                                                  Text(
                                                    'Tax classification: ${receiptTaxLabel(sale)}',
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
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
