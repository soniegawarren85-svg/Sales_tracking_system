import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StaffNotificationPage extends StatelessWidget {
  const StaffNotificationPage({super.key});

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE91E63),
        title: Text(
          'Staff Reports',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: currentUser == null
          ? Center(
              child: Text(
                'Please sign in to view your reports.',
                style: GoogleFonts.dmSans(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('daily_reports')
                  .where('staffId', isEqualTo: currentUser.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load reports.',
                      style: GoogleFonts.dmSans(fontSize: 16),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No reports found yet. Your daily reports will appear here once they are submitted.',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final title = data['title']?.toString() ?? 'Report';
                    final message = data['message']?.toString() ?? '';
                    final timestamp = data['createdAt'] as Timestamp?;
                    final date = timestamp?.toDate() ?? DateTime.now();
                    final totalSales =
                        (data['totalSales'] as num?)?.toDouble() ?? 0.0;
                    final cashDrawer =
                        (data['cashDrawerTotal'] as num?)?.toDouble() ?? 0.0;
                    final transactionCount =
                        data['transactionCount']?.toString() ?? '0';

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showReportDetail(context, data),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: GoogleFonts.playfairDisplay(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDate(date),
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                message,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _InfoChip(
                                    label: 'Sales',
                                    value: '₱${totalSales.toStringAsFixed(2)}',
                                  ),
                                  const SizedBox(width: 8),
                                  _InfoChip(
                                    label: 'Transactions',
                                    value: transactionCount,
                                  ),
                                  const SizedBox(width: 8),
                                  _InfoChip(
                                    label: 'Drawer',
                                    value: '₱${cashDrawer.toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _formatTime(date),
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showReportDetail(BuildContext context, Map<String, dynamic> data) {
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp?.toDate() ?? DateTime.now();
    final totalSales = (data['totalSales'] as num?)?.toDouble() ?? 0.0;
    final cashDrawer = (data['cashDrawerTotal'] as num?)?.toDouble() ?? 0.0;
    final transactionCount = data['transactionCount']?.toString() ?? '0';
    final reportDate = data['reportDate']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          data['title']?.toString() ?? 'Report details',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              data['message']?.toString() ?? '',
              style: GoogleFonts.dmSans(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Report date: $reportDate',
              style: GoogleFonts.dmSans(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              'Created: ${_formatDate(date)} ${_formatTime(date)}',
              style: GoogleFonts.dmSans(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Text(
              'Total sales: ₱${totalSales.toStringAsFixed(2)}',
              style: GoogleFonts.dmSans(fontSize: 14),
            ),
            Text(
              'Cash drawer: ₱${cashDrawer.toStringAsFixed(2)}',
              style: GoogleFonts.dmSans(fontSize: 14),
            ),
            Text(
              'Transactions: $transactionCount',
              style: GoogleFonts.dmSans(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: GoogleFonts.dmSans()),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
