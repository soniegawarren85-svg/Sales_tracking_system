import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../services/branch_status.dart';
import '../widgets/admin_sales_overview.dart';
import '../theme/app_colors.dart';

int currentAllocatedQuantity(BranchReportData report, DateTime day) {
  final branchIds = report
      .rows('branches')
      .where(isActiveBranch)
      .map((branch) => '${branch['_id'] ?? ''}')
      .where((id) => id.isNotEmpty)
      .toSet();

  final start = DateUtils.dateOnly(day);
  final end = start.add(const Duration(days: 1));
  return branchIds.fold<int>(
    0,
    (total, branchId) =>
        total +
        report
            .items(branchId, start, end)
            .fold<int>(
              0,
              (sum, item) => sum + reportValue(item['added']).round(),
            ),
  );
}

int superAdminCashierCount(Iterable<Map<String, dynamic>> accounts) {
  final counted = <String>{};
  for (final account in accounts) {
    final status = '${account['status'] ?? ''}'.trim().toLowerCase();
    if (status != 'accepted' ||
        account['isDeleted'] == true ||
        account['isVoided'] == true) {
      continue;
    }

    final role = '${account['role'] ?? ''}'.trim().toLowerCase();
    final staffId = '${account['staffId'] ?? account['username'] ?? ''}'.trim();
    final isCashier =
        role == 'staff' ||
        role == 'cashier' ||
        (role.isEmpty &&
            '${account['adminId'] ?? ''}'.trim().isEmpty &&
            staffId.isNotEmpty);
    if (!isCashier) continue;

    final id =
        '${account['uid'] ?? account['userId'] ?? account['_id'] ?? staffId}'
            .trim();
    if (id.isNotEmpty) counted.add(id);
  }
  return counted.length;
}

int allocatedQuantityFromHistory(
  Iterable<Map<String, dynamic>> history,
  Set<String> activeBranchIds,
) => history
    .where((row) {
      final type = '${row['type'] ?? ''}'.toLowerCase();
      return activeBranchIds.contains('${row['staffId']}') &&
          (type.isEmpty || type == 'assignment');
    })
    .fold<int>(0, (total, row) {
      final items = row['items'];
      if (items is List) {
        return total +
            items.whereType<Map>().fold<int>(
              0,
              (sum, item) => sum + reportValue(item['quantity']).round(),
            );
      }
      final quantities = row['quantities'];
      if (quantities is Map) {
        return total +
            quantities.values.fold<int>(
              0,
              (sum, quantity) => sum + reportValue(quantity).round(),
            );
      }
      return total;
    });

class SuperAdminTotals extends StatefulWidget {
  const SuperAdminTotals({super.key});

  @override
  State<SuperAdminTotals> createState() => _SuperAdminTotalsState();
}

class _SuperAdminTotalsState extends State<SuperAdminTotals> {
  late DateTime _today;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sales;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _allocations;
  final _branches = FirebaseFirestore.instance
      .collection('branches')
      .snapshots();
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _watchToday();
  }

  void _watchToday() {
    _midnight?.cancel();
    final now = DateTime.now();
    _today = DateUtils.dateOnly(now);
    final end = _today.add(const Duration(days: 1));
    final startTimestamp = Timestamp.fromDate(_today);
    final endTimestamp = Timestamp.fromDate(end);
    final firestore = FirebaseFirestore.instance;
    _sales = firestore
        .collection('completed_sales')
        .where('timestamp', isGreaterThanOrEqualTo: startTimestamp)
        .where('timestamp', isLessThan: endTimestamp)
        .snapshots();
    _allocations = firestore
        .collection('staff_inventory_history')
        .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
        .where('createdAt', isLessThan: endTimestamp)
        .snapshots();
    _midnight = Timer(end.difference(now), () {
      if (mounted) setState(_watchToday);
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _branches,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Unable to load overall totals.');
      }
      if (!snapshot.hasData) return _totalsSkeleton(context);

      final branchIds = snapshot.data!.docs
          .where((doc) => isActiveBranch(doc.data()))
          .map((doc) => doc.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _sales,
        builder: (context, salesSnapshot) {
          if (salesSnapshot.hasError) {
            return const Text('Unable to load overall totals.');
          }
          if (!salesSnapshot.hasData) return _totalsSkeleton(context);
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _allocations,
            builder: (context, allocationsSnapshot) {
              if (allocationsSnapshot.hasError) {
                return const Text('Unable to load overall totals.');
              }
              if (!allocationsSnapshot.hasData) {
                return _totalsSkeleton(context);
              }
              final sales = completedReceipts(
                salesSnapshot.data!.docs
                    .map((doc) => doc.data())
                    .where((sale) => branchIds.contains(sale['branchId'])),
              );
              final allocated = allocatedQuantityFromHistory(
                allocationsSnapshot.data!.docs.map((doc) => doc.data()),
                branchIds,
              );
              final values = <(String, String, IconData)>[
                ('Total allocated', '$allocated', Icons.inventory_2_outlined),
                ('Total transactions', '${sales.length}', Icons.receipt_long),
                (
                  'Total branches',
                  '${branchIds.length}',
                  Icons.storefront_outlined,
                ),
              ];
              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 600
                      ? 2
                      : values.length;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: values
                        .map(
                          (value) => SizedBox(
                            width:
                                (constraints.maxWidth - (columns - 1) * 12) /
                                columns,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.blush),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(value.$3, color: AppColors.primary),
                                  const SizedBox(height: 10),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      value.$2,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ),
                                  Text(value.$1),
                                  const Text(
                                    'Today',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              );
            },
          );
        },
      );
    },
  );

  Widget _totalsSkeleton(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 600 ? 2 : 3;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          3,
          (_) => SizedBox(
            width: width,
            child: Container(
              height: 128,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.blush),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBar(24, 24),
                  const SizedBox(height: 12),
                  _skeletonBar(90, 24),
                  const SizedBox(height: 8),
                  _skeletonBar(120, 12),
                  const Spacer(),
                  _skeletonBar(45, 10),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _skeletonBar(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF3E4E9),
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
