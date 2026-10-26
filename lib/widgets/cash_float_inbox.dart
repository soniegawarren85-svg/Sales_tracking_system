import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/cash_float_service.dart';
import '../services/session_actor.dart';

class CashFloatInbox extends StatelessWidget {
  const CashFloatInbox({
    super.key,
    required this.branchId,
    required this.role,
    this.compact = false,
  });

  final String branchId;
  final String role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (branchId.trim().isEmpty) return const SizedBox.shrink();
    final firestore = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection(CashFloatService.collectionName)
          .where('branchId', isEqualTo: branchId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Tooltip(
            message: 'Unable to check cash float requests.',
            child: Icon(Icons.error_outline, color: Colors.red),
          );
        }
        final pending = (snapshot.data?.docs ?? const [])
            .where(
              (doc) =>
                  doc.data()['status'] == 'pending' &&
                  doc.data()['recipientRole'] == role.toLowerCase(),
            )
            .toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        return TextButton.icon(
          onPressed: () => _showRequests(context, pending),
          icon: _CountBadge(count: pending.length),
          label: Text(compact ? 'Cash float' : 'Pending cash float'),
          style: TextButton.styleFrom(
            foregroundColor: compact ? Colors.white : const Color(0xFF9D174D),
            backgroundColor: compact
                ? Colors.white.withValues(alpha: 0.16)
                : const Color(0xFFFFF1F5),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 9,
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRequests(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cash float requests'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: requests.map((request) {
              final data = request.data();
              final amount = (data['amount'] as num?)?.toDouble() ?? 0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['branchName'] ?? 'Branch'} · ₱${amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('Sent by ${data['senderName'] ?? 'Super Admin'}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _receive(context, dialogContext, request.id),
                            child: const Text('Received'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _report(context, dialogContext, request.id),
                            child: const Text('Report not received'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _receive(
    BuildContext context,
    BuildContext dialogContext,
    String requestId,
  ) async {
    try {
      final actor = await resolveSessionActor(
        FirebaseFirestore.instance,
        admin: role.toLowerCase() == 'admin',
      );
      await CashFloatService.receive(
        firestore: FirebaseFirestore.instance,
        requestId: requestId,
        actorId: actor.id,
        actorName: actor.name,
        actorRole: role,
      );
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash float received and recorded.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to confirm receipt: $error')),
        );
      }
    }
  }

  Future<void> _report(
    BuildContext context,
    BuildContext dialogContext,
    String requestId,
  ) async {
    final reason = ValueNotifier<String>('Cash did not arrive');
    final message = TextEditingController();
    final report = await showDialog<({String reason, String message})>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Report cash not received'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: reason,
                builder: (context, value, _) => DropdownButtonFormField<String>(
                  initialValue: value,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Cash did not arrive',
                      child: Text('Cash did not arrive'),
                    ),
                    DropdownMenuItem(
                      value: 'Amount is incorrect',
                      child: Text('Amount is incorrect'),
                    ),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) reason.value = value;
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: message,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional message (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              reason: reason.value,
              message: message.text.trim(),
            )),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    reason.dispose();
    message.dispose();
    if (report == null) return;
    try {
      final actor = await resolveSessionActor(
        FirebaseFirestore.instance,
        admin: role.toLowerCase() == 'admin',
      );
      await CashFloatService.reportNotReceived(
        firestore: FirebaseFirestore.instance,
        requestId: requestId,
        actorId: actor.id,
        actorName: actor.name,
        actorRole: role,
        reason: report.reason,
        message: report.message,
      );
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash float report submitted.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to submit report: $error')),
        );
      }
    }
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xFFE11D48),
      shape: BoxShape.circle,
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
