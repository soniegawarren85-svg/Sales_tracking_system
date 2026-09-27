import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'admin_catalog.dart';
import 'inventory_records_table.dart';

Future<void> showBundleDetails(
  BuildContext context,
  AdminCatalogEntry entry,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final items = catalogBundleContents(entry.source);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
              color: AppColors.primaryDark,
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${entry.id} · ${items.length} items',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: InventoryRecordsTable(
                  headings: const ['Item', 'Expiration date', 'Qty'],
                  flex: const {0: 3, 1: 2, 2: .8},
                  rows: items
                      .map(
                        (item) => <Widget>[
                          Text(
                            '${item['name'] ?? 'Item'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${item['expirationDate'] ?? 'Not recorded'}'
                                .split('T')
                                .first,
                          ),
                          Text(
                            '×${item['quantity'] ?? 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      )
                      .toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
