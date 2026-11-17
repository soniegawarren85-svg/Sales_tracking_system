import 'package:flutter/material.dart';

class LowStockReportMessageCard extends StatelessWidget {
  const LowStockReportMessageCard({
    super.key,
    required this.items,
    required this.mine,
  });

  final List items;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final textColor = mine ? Colors.white : const Color(0xFF71310D);
    final surface = mine ? Colors.white.withOpacity(0.14) : const Color(0xFFFFF3E8);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(
          color: mine ? Colors.white54 : const Color(0xFFFFB46A),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOW-STOCK REQUEST',
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final raw in items.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Builder(
                builder: (context) {
                  final item = Map<String, dynamic>.from(raw);
                  final madeToOrder = [
                    'Beverages',
                    'Add-ons',
                  ].contains('${item['type'] ?? ''}');
                  final requested = item['requestedQuantity'];
                  final current = item['currentStock'] ??
                      item['remaining'] ??
                      item['stock'];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['name'] ?? 'Item'}'
                        ' · ${item['categoryName'] ?? item['type'] ?? 'Inventory'}',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Available: ${current ?? 'Not recorded'}'
                        '  •  Request: ${madeToOrder ? 'Made to order' : requested ?? 'Not specified'}',
                        style: TextStyle(color: textColor, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
