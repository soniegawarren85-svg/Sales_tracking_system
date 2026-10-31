import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/number_format.dart';

class HeldOrderCard extends StatelessWidget {
  const HeldOrderCard({
    super.key,
    required this.data,
    required this.hasNetwork,
    required this.onVoid,
    required this.onRestore,
  });

  final Map<String, dynamic> data;
  final bool? hasNetwork;
  final VoidCallback onVoid;
  final VoidCallback onRestore;

  String get syncLabel {
    if (data['_pendingSync'] != true) return 'Synced';
    if (hasNetwork == false) return 'Saved offline';
    if (hasNetwork == true) return 'Sync pending';
    return 'Sync status unknown';
  }

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final created = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : data['createdAt'] is DateTime
        ? data['createdAt'] as DateTime
        : DateTime.tryParse('${data['createdAt'] ?? ''}');
    final discountApplied = data['discountApplied'] == true;
    final discountType = data['discountType']?.toString().trim() ?? '';
    final discountId = data['discountId']?.toString().trim() ?? '';

    return Card(
      elevation: 1,
      color: const Color(0xFFFFF8FA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE9C9D9)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Held order',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: data['_pendingSync'] == true
                        ? (hasNetwork == false
                              ? const Color(0xFFFFF0D8)
                              : const Color(0xFFEAF2FF))
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    syncLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (created != null) ...[
              const SizedBox(height: 3),
              Text(
                MaterialLocalizations.of(context).formatShortDate(created),
                style: const TextStyle(color: Color(0xFF8A7080), fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            ...items.map((item) {
              final name = item['name']?.toString().trim() ?? '';
              final variant = item['variant']?.toString().trim() ?? '';
              final quantity = item['quantity'];
              final price = item['price'];
              final numericPrice = price is num ? price : null;
              final numericQuantity = quantity is num ? quantity : 0;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${name.isEmpty ? 'Item' : name}  ×$numericQuantity',
                      style: const TextStyle(
                        color: Color(0xFF54203F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (variant.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          variant,
                          style: const TextStyle(
                            color: Color(0xFF8A7080),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (numericPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '${formatMoney(numericPrice)} each · ${formatMoney(numericPrice * numericQuantity)}',
                          style: const TextStyle(
                            color: Color(0xFF6D5665),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (discountApplied &&
                ((discountType.isNotEmpty && discountType != 'None') ||
                    discountId.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  [
                    if (discountType.isNotEmpty && discountType != 'None')
                      'Discount: $discountType',
                    if (discountId.isNotEmpty) 'Option ID: $discountId',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF784B20),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onVoid, child: const Text('Void')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onRestore,
                  child: const Text('Restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
