import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/branch_session.dart';

class BranchAccessPage extends StatefulWidget {
  const BranchAccessPage({super.key});

  @override
  State<BranchAccessPage> createState() => _BranchAccessPageState();
}

class _BranchAccessPageState extends State<BranchAccessPage> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  Future<void> _switchBranch({String? id, required String name}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Switch branch?'),
        content: Text(
          'Open the admin system for $name? Dashboard data will be limited to this branch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Switching branch...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await BranchSession.instance.switchTo(branchId: id, branchName: name);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isExpired(String value) {
    if (value.trim().isEmpty) return false;
    try {
      final expiry = DateTime.parse(value);
      final today = DateTime.now();
      return expiry.isBefore(DateTime(today.year, today.month, today.day + 1));
    } catch (_) {
      return false;
    }
  }

  bool _hasExpiredBundleItem(Map<String, dynamic> data) {
    final items = [
      ...(data['items'] as List<dynamic>? ?? []),
      ...((data['bundleInstances'] as List<dynamic>? ?? []).expand((instance) {
        return instance is Map
            ? (instance['items'] as List<dynamic>? ?? [])
            : [];
      })),
    ];
    return items.whereType<Map>().any(
      (item) => _isExpired(item['expirationDate']?.toString() ?? ''),
    );
  }

  int _availableBundleCount(Map<String, dynamic> data) {
    final instances = data['bundleInstances'] as List<dynamic>? ?? [];
    if (instances.isEmpty) return _parseInt(data['bundleCount']);
    return instances.where((instance) {
      if (instance is! Map) return false;
      return (instance['status']?.toString().toLowerCase() ?? 'available') ==
          'available';
    }).length;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _currentAssignedInventory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final sourceSnapshot = await _firestore.collection('sales_inventory').get();
    final activeSources = <String, Map<String, dynamic>>{};
    final activeSourcesByName = <String, Map<String, dynamic>>{};
    for (final source in sourceSnapshot.docs) {
      final data = source.data();
      if (data['isDeleted'] == true) continue;
      activeSources[source.id] = data;
      final name = data['name']?.toString().trim().toLowerCase() ?? '';
      if (name.isNotEmpty) activeSourcesByName[name] = data;
    }

    String itemKey(Map<String, dynamic> item) =>
        '${item['name'] ?? ''}|${item['price'] ?? ''}'.toLowerCase();

    return docs.where((doc) {
      final data = doc.data();
      if (data['isDeleted'] == true) return false;
      if (data['isCoffee'] == true || data['isAddon'] == true) return true;

      final sourceId = data['sourceInventoryId']?.toString().trim() ?? '';
      final name = data['name']?.toString().trim().toLowerCase() ?? '';
      final source = activeSources[sourceId] ?? activeSourcesByName[name];
      if (source == null) return false;

      if (data['isBundle'] == true) {
        return source['isBundle'] == true &&
            !_hasExpiredBundleItem(data) &&
            !_hasExpiredBundleItem(source) &&
            _availableBundleCount(data) > 0;
      }

      final sourceItems = ((source['items'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((item) => itemKey(Map<String, dynamic>.from(item)))
          .toSet();
      return ((data['items'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .any((item) {
            final stock = item.containsKey('stock')
                ? _parseInt(item['stock'])
                : _parseInt(item['startingStock']);
            return stock > 0 &&
                !_isExpired(item['expirationDate']?.toString() ?? '') &&
                (sourceItems.isEmpty || sourceItems.contains(itemKey(item)));
          });
    }).toList();
  }

  Widget _branchCashDrawer(
    String? branchId,
    List<String> staffIds,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> staffDocs,
  ) {
    final ownerIds = <String>{...staffIds.map((id) => id.trim())};
    for (final doc in staffDocs) {
      final data = doc.data();
      ownerIds.addAll(
        {
          doc.id,
          data['uid']?.toString() ?? '',
          data['userId']?.toString() ?? '',
          data['staffId']?.toString() ?? '',
        }..removeWhere((id) => id.trim().isEmpty),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('staff_cash_drawer').snapshots(),
      builder: (_, snapshot) {
        var total = 0.0;
        var matchedStaffDrawer = false;
        QueryDocumentSnapshot<Map<String, dynamic>>? branchDrawer;
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          final identifiers = <String>{
            doc.id,
            data['staffId']?.toString() ?? '',
            data['userId']?.toString() ?? '',
            data['uid']?.toString() ?? '',
          }..removeWhere((id) => id.trim().isEmpty);
          if (branchId != null && doc.id == branchId) {
            branchDrawer = doc;
          }
          if (!identifiers.any(ownerIds.contains)) continue;
          matchedStaffDrawer = true;
          total +=
              (data['balance'] as num?)?.toDouble() ??
              (data['cashDrawer'] as num?)?.toDouble() ??
              0;
        }
        if (!matchedStaffDrawer && branchDrawer != null) {
          final data = branchDrawer.data();
          total =
              (data['balance'] as num?)?.toDouble() ??
              (data['cashDrawer'] as num?)?.toDouble() ??
              0;
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF8BBD0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFFD81B60),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cash drawer',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF9C1650),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showBranchDetails({
    String? id,
    required String name,
    required List<String> staffIds,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .82,
        minChildSize: .55,
        maxChildSize: .94,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFF8FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Branch details',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF262238),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: id == null
                      ? Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
                      : _firestore
                            .collection('staff_inventory')
                            .where('staffId', isEqualTo: id)
                            .snapshots(),
                  builder: (_, inventorySnapshot) =>
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _firestore
                            .collection('staff_requests')
                            .snapshots(),
                        builder: (_, staffSnapshot) {
                          final inventory = inventorySnapshot.data?.docs ?? [];
                          final assignedStaff = (staffSnapshot.data?.docs ?? [])
                              .where((doc) {
                                final data = doc.data();
                                final status = data['status']
                                    ?.toString()
                                    .toLowerCase();
                                if (status != null && status != 'accepted') {
                                  return false;
                                }
                                final identifiers = <String>{
                                  doc.id,
                                  data['uid']?.toString() ?? '',
                                  data['userId']?.toString() ?? '',
                                  data['staffId']?.toString() ?? '',
                                }..removeWhere((id) => id.trim().isEmpty);
                                return identifiers.any(staffIds.contains);
                              })
                              .toList();
                          return FutureBuilder<
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          >(
                            future: id == null
                                ? Future.value(inventory)
                                : _currentAssignedInventory(inventory),
                            builder: (_, currentInventorySnapshot) {
                              final currentInventory =
                                  currentInventorySnapshot.data ?? [];
                              return ListView(
                                controller: controller,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  20,
                                  20,
                                ),
                                children: [
                                  _detailTitle(
                                    'Assigned staff (${assignedStaff.length})',
                                  ),
                                  if (assignedStaff.isEmpty)
                                    const _BranchEmpty(
                                      message:
                                          'No staff assigned to this branch yet.',
                                    )
                                  else
                                    ...assignedStaff.map((doc) {
                                      final data = doc.data();
                                      final fullName =
                                          [data['firstName'], data['lastName']]
                                              .where(
                                                (v) =>
                                                    v != null &&
                                                    v
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty,
                                              )
                                              .join(' ');
                                      return ListTile(
                                        leading: const CircleAvatar(
                                          child: Icon(Icons.person_rounded),
                                        ),
                                        title: Text(
                                          fullName.isEmpty
                                              ? 'Staff member'
                                              : fullName,
                                        ),
                                        subtitle: Text(
                                          data['email']?.toString() ??
                                              'Assigned staff',
                                        ),
                                      );
                                    }),
                                  _branchCashDrawer(
                                    id,
                                    staffIds,
                                    assignedStaff,
                                  ),
                                  _detailTitle(
                                    'Allocated items (${currentInventory.length})',
                                  ),
                                  if (id == null)
                                    const _BranchEmpty(
                                      message:
                                          'Main Branch uses the full inventory list.',
                                    )
                                  else if (currentInventorySnapshot
                                          .connectionState ==
                                      ConnectionState.waiting)
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (currentInventory.isEmpty)
                                    const _BranchEmpty(
                                      message:
                                          'No items allocated to this branch yet.',
                                    )
                                  else
                                    ...currentInventory.map((doc) {
                                      final data = doc.data();
                                      return ListTile(
                                        leading: const Icon(
                                          Icons.inventory_2_rounded,
                                          color: Color(0xFFD81B60),
                                        ),
                                        title: Text(
                                          data['name']?.toString() ??
                                              data['item']?.toString() ??
                                              'Inventory item',
                                        ),
                                        subtitle: Text(
                                          data['category']?.toString() ??
                                              'Allocated item',
                                        ),
                                      );
                                    }),
                                ],
                              );
                            },
                          );
                        },
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _switchBranch(id: id, name: name);
                    },
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text('Switch to $name'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Color(0xFF9C1650),
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    BranchSession.instance.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createBranch() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Branch name',
            hintText: 'SM Dagupan',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    await _firestore.collection('branches').add({
      'name': name,
      'staffIds': <String>[],
      'staffNames': <String>[],
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  DateTime? _timestampDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  String _formatDate(dynamic value) {
    final date = _timestampDate(value);
    if (date == null) return 'Date unavailable';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} $hour:$minute $period';
  }

  Future<void> _showBranchHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Branch history')),
            IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore.collection('branches').snapshots(),
            builder: (_, snapshot) {
              final history = [...(snapshot.data?.docs ?? [])]
                ..sort((a, b) {
                  final aDate = _timestampDate(a.data()['createdAt']);
                  final bDate = _timestampDate(b.data()['createdAt']);
                  return (bDate ?? DateTime(0)).compareTo(aDate ?? DateTime(0));
                });
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (history.isEmpty) {
                return const _BranchEmpty(message: 'No branch history yet.');
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final data = history[index].data();
                    final isVoided = data['isVoided'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isVoided
                            ? Icons.block_rounded
                            : Icons.storefront_rounded,
                        color: isVoided ? Colors.red : const Color(0xFFD81B60),
                      ),
                      title: Text(
                        data['name']?.toString() ?? 'Branch',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        isVoided
                            ? 'Created: ${_formatDate(data['createdAt'])}\nVoided: ${_formatDate(data['voidedAt'])}'
                            : 'Created: ${_formatDate(data['createdAt'])}',
                      ),
                      isThreeLine: isVoided,
                      trailing: Text(
                        isVoided ? 'VOIDED' : 'ACTIVE',
                        style: TextStyle(
                          color: isVoided
                              ? Colors.red
                              : const Color(0xFFD81B60),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAlreadyInBranchMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Already in Branch access.')),
      );
  }

  Future<void> _editBranch(String branchId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Branch name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == currentName) return;
    await _firestore.collection('branches').doc(branchId).update({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _voidBranch(String branchId, String branchName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void Branch?'),
        content: Text(
          'Void "$branchName"? Its data will remain available, but the branch will be hidden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _firestore.collection('branches').doc(branchId).update({
      'isVoided': true,
      'voidedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5EEF0);
    const primary = Color(0xFFD81B60);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Branch access',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('branches').snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final visibleDocs =
              docs.where((doc) {
                if (doc.data()['isVoided'] == true) return false;
                final name = doc.data()['name']?.toString().toLowerCase() ?? '';
                final query = _searchQuery.toLowerCase();
                return query.isEmpty || name.contains(query);
              }).toList()..sort(
                (a, b) => (a.data()['name']?.toString() ?? '')
                    .toLowerCase()
                    .compareTo(
                      (b.data()['name']?.toString() ?? '').toLowerCase(),
                    ),
              );

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Branches',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF262238),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search branches',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: primary.withOpacity(0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: primary.withOpacity(0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListenableBuilder(
                        listenable: BranchSession.instance,
                        builder: (_, __) => _BranchCard(
                          name: 'Main Branch',
                          staffCount: 0,
                          showStaffCount: false,
                          isActive: BranchSession.instance.isMainBranch,
                          onTap: BranchSession.instance.isMainBranch
                              ? _showAlreadyInBranchMessage
                              : () => _showBranchDetails(
                                  id: null,
                                  name: 'Main Branch',
                                  staffIds: const [],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final buttonWidth = constraints.maxWidth >= 400
                              ? 190.0
                              : (constraints.maxWidth - 10) / 2;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              SizedBox(width: 10),
                              SizedBox(
                                width: buttonWidth,
                                child: OutlinedButton.icon(
                                  onPressed: _createBranch,
                                  icon: const Icon(Icons.add_business_rounded),
                                  label: const Text('Create'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    side: BorderSide(
                                      color: primary.withOpacity(.5),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                child: OutlinedButton.icon(
                                  onPressed: _showBranchHistory,
                                  icon: const Icon(Icons.history_rounded),
                                  label: const Text('View history'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    side: BorderSide(
                                      color: primary.withOpacity(.5),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleDocs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                    child: _EmptyBranches(hasSearch: _searchQuery.isNotEmpty),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _BranchCard(
                        name:
                            visibleDocs[index].data()['name']?.toString() ??
                            'Branch',
                        staffCount:
                            (visibleDocs[index].data()['staffIds']
                                        as List<dynamic>? ??
                                    [])
                                .length,
                        isActive:
                            BranchSession.instance.branchId ==
                            visibleDocs[index].id,
                        onEdit: () => _editBranch(
                          visibleDocs[index].id,
                          visibleDocs[index].data()['name']?.toString() ??
                              'Branch',
                        ),
                        onVoid: () => _voidBranch(
                          visibleDocs[index].id,
                          visibleDocs[index].data()['name']?.toString() ??
                              'Branch',
                        ),
                        onTap: () => _showBranchDetails(
                          id: visibleDocs[index].id,
                          name:
                              visibleDocs[index].data()['name']?.toString() ??
                              'Branch',
                          staffIds:
                              (visibleDocs[index].data()['staffIds']
                                          as List<dynamic>? ??
                                      [])
                                  .map((id) => id.toString())
                                  .toList(),
                        ),
                      ),
                      childCount: visibleDocs.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final String name;
  final int staffCount;
  final bool showStaffCount;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onVoid;

  const _BranchCard({
    required this.name,
    required this.staffCount,
    this.showStaffCount = true,
    this.isActive = false,
    this.onTap,
    this.onEdit,
    this.onVoid,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2B5CC)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFCE4EC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: Color(0xFFD81B60),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF262238),
                    ),
                  ),
                  if (isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text(
                        'CURRENT BRANCH',
                        style: TextStyle(
                          color: Color(0xFFD81B60),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (showStaffCount) ...[
                    const SizedBox(height: 4),
                    Text(
                      staffCount == 1
                          ? '1 staff assigned'
                          : '$staffCount staff assigned',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null || onVoid != null) ...[
              IconButton(
                tooltip: 'Edit branch',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                color: const Color(0xFFD81B60),
              ),
              IconButton(
                tooltip: 'Void branch',
                onPressed: onVoid,
                icon: const Icon(Icons.block_rounded),
                color: Colors.red,
              ),
            ],
            Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: isActive
                  ? const Color(0xFFD81B60)
                  : const Color(0xFFBDB5BE),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBranches extends StatelessWidget {
  final bool hasSearch;

  const _EmptyBranches({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_tree_outlined,
            color: Color(0xFFD81B60),
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            hasSearch ? 'No branch found' : 'No branches yet',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF262238),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasSearch
                ? 'Try another branch name.'
                : 'Create your first branch above.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _BranchEmpty extends StatelessWidget {
  final String message;
  const _BranchEmpty({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
  );
}
