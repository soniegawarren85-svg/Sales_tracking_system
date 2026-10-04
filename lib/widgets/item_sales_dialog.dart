import 'package:flutter/material.dart';
import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';
import 'horizontal_controls.dart';

class ItemSalesDialog extends StatefulWidget {
  const ItemSalesDialog({super.key, required this.items, required this.period});
  final List<Map<String, dynamic>> items;
  final String period;
  @override
  State<ItemSalesDialog> createState() => _ItemSalesDialogState();
}

class _ItemSalesDialogState extends State<ItemSalesDialog> {
  String query = '', type = 'All';
  @override
  Widget build(BuildContext context) {
    final rows = widget.items
        .where(
          (item) =>
              (type == 'All' ||
                  item['type'] == type ||
                  (type == 'Beverages' && item['type'] == 'Add-ons')) &&
              '${item['name']} ${item['id']} ${item['branchName']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 780,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Container(
              color: AppColors.primaryDeep,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Item sales',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close item sales',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.period,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (value) =>
                        setState(() => query = value.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search items or branches',
                    ),
                  ),
                  const SizedBox(height: 8),
                  HorizontalControls(
                    children: [
                      for (final value in [
                        'All',
                        'Categories',
                        'Bundle',
                        'Beverages',
                      ])
                        ChoiceChip(
                          label: Text(value),
                          selected: type == value,
                          onSelected: (_) => setState(() => type = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total sales: ₱${rows.fold<double>(0, (sum, row) => sum + reportValue(row['sales'])).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No item sales for this period.',
                        style: TextStyle(fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${item['branchName'] ?? ''} • ${item['type']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Sold: ${reportValue(item['sold']).toStringAsFixed(0)}',
                                ),
                                Text(
                                  'Sales: ₱${reportValue(item['sales']).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.primaryDeep,
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
        ),
      ),
    );
  }
}
