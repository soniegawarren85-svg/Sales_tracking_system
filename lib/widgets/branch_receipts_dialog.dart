import 'package:flutter/material.dart';
import '../services/refund_value.dart';

import '../services/branch_report_data.dart';
import '../theme/app_colors.dart';
import 'admin_recent_sales.dart';
import 'historical_cash_drawer.dart';

class BranchReceiptsDialog extends StatefulWidget {
  const BranchReceiptsDialog({
    super.key,
    required this.sales,
    required this.period,
    this.title = 'All receipts',
    this.reductions = false,
    this.recordsStream,
  });
  final List<Map<String, dynamic>> sales;
  final String period, title;
  final bool reductions;
  final Stream<List<Map<String, dynamic>>>? recordsStream;
  @override
  State<BranchReceiptsDialog> createState() => _BranchReceiptsDialogState();
}

class _BranchReceiptsDialogState extends State<BranchReceiptsDialog> {
  String _search = '', _payment = 'All';
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: widget.recordsStream,
    initialData: widget.sales,
    builder: (context, snapshot) {
      final rows =
          (snapshot.data ?? widget.sales)
              .map(refundValueRecord)
              .where(
                (row) =>
                    (_payment == 'All' ||
                        (_payment == 'Discounted' &&
                            reportValue(row['discount']) > 0) ||
                        '${row['paymentMode'] ?? row['paymentMethod'] ?? (widget.reductions ? '' : 'Cash')}'
                                .toLowerCase() ==
                            _payment.toLowerCase()) &&
                    row.values.join(' ').toLowerCase().contains(_search),
              )
              .toList()
            ..sort(
              (a, b) =>
                  (cashRecordDate(b['timestamp'] ?? b['createdAt']) ??
                          DateTime(0))
                      .compareTo(
                        cashRecordDate(a['timestamp'] ?? a['createdAt']) ??
                            DateTime(0),
                      ),
            );
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: 820,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              Container(
                color: AppColors.primaryDeep,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close receipts',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText:
                        'Search receipt ID, staff, items or payment details',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children:
                        [
                              'All',
                              'GCash',
                              'Cash',
                              if (!widget.reductions) 'Discounted',
                            ]
                            .map(
                              (mode) => ChoiceChip(
                                label: Text(mode),
                                selected: _payment == mode,
                                onSelected: (_) =>
                                    setState(() => _payment = mode),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${rows.length} ${widget.reductions ? 'records' : 'receipts'}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No receipts match these filters.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final sale = rows[index];
                          final at = cashRecordDate(
                            sale['timestamp'] ?? sale['createdAt'],
                          );
                          final amount = widget.reductions
                              ? reportValue(
                                  sale['lossAmount'] ??
                                      reportValue(sale['quantity']) *
                                          reportValue(
                                            sale['unitPrice'] ??
                                                sale['bundlePrice'],
                                          ),
                                )
                              : reportValue(sale['total']);
                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: AppColors.blush,
                                      child: Icon(
                                        Icons.receipt_long,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '${sale['salesId'] ?? sale['itemName'] ?? sale['_id'] ?? 'Record'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '₱${amount.abs().toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  at == null
                                      ? 'Date not recorded'
                                      : '${MaterialLocalizations.of(context).formatMediumDate(at)} • ${TimeOfDay.fromDateTime(at).format(context)}',
                                ),
                                Text(
                                  widget.reductions
                                      ? '${sale['quantity'] ?? 0} reduced'
                                      : '${sale['paymentMode'] ?? sale['paymentMethod'] ?? 'Cash'} • ${saleStatus(sale)}',
                                ),
                                if (sale['reason'] != null ||
                                    sale['refundReason'] != null)
                                  Text(
                                    '${sale['reason'] ?? sale['refundReason']}',
                                  ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('View details'),
                                    onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => widget.reductions
                                          ? AlertDialog(
                                              title: Text(
                                                '${sale['itemName'] ?? 'Reduced item'}',
                                              ),
                                              content: Text(
                                                '${sale['quantity'] ?? 0} reduced\n₱${amount.toStringAsFixed(2)}\n${sale['reason'] ?? ''}\n${at ?? ''}',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('Close'),
                                                ),
                                              ],
                                            )
                                          : ReceiptDetails(
                                              id: '${sale['_id'] ?? sale['salesId']}',
                                              sale: sale,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
