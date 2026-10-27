import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/cash_float_service.dart';
import '../services/number_format.dart';
import '../services/session_actor.dart';

class CashFloatConversationCard extends StatefulWidget {
  const CashFloatConversationCard({
    super.key,
    required this.requestId,
    required this.chatId,
    required this.role,
    this.firestore,
  });

  final String requestId;
  final String chatId;
  final String role;
  final FirebaseFirestore? firestore;

  @override
  State<CashFloatConversationCard> createState() =>
      _CashFloatConversationCardState();
}

class _CashFloatConversationCardState extends State<CashFloatConversationCard> {
  static const _raspberry = Color(0xFFBE185D);
  static const _darkRaspberry = Color(0xFF881337);
  bool _saving = false;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  String _money(dynamic value) =>
      formatMoney(value is num ? value : double.tryParse('$value') ?? 0);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection(CashFloatService.collectionName)
          .doc(widget.requestId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _cardShell(const Text('Unable to load cash float details.'));
        }
        final data = snapshot.data?.data();
        if (data == null) {
          return _cardShell(
            const Text('This cash float request is no longer available.'),
          );
        }
        final amount = data['amount'];
        final status = '${data['status'] ?? 'pending'}';
        final canRespond =
            status == 'pending' &&
            widget.role.toLowerCase() ==
                '${data['recipientRole'] ?? ''}'.toLowerCase();
        final isShort = data['reportReason'] == 'Amount is short';

        return _cardShell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .17),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cash float',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${data['branchName'] ?? 'Branch'} · ${data['requestType'] == 'starting' ? 'Starting cash' : 'Additional cash'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(status, isShort),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: _raspberry,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Allocated amount',
                        style: TextStyle(
                          color: Color(0xFF7A5261),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _money(amount),
                      style: const TextStyle(
                        color: _darkRaspberry,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (status == 'received' || status == 'reported') ...[
                const SizedBox(height: 12),
                _statusDetails(data, isShort),
              ],
              if (canRespond) ...[
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 310;
                    final receive = FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _confirmReceipt(data, amount),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Receive'),
                      style: FilledButton.styleFrom(
                        foregroundColor: _darkRaspberry,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    );
                    final report = OutlinedButton.icon(
                      onPressed: _saving ? null : () => _report(data, amount),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Report'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .7),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    );
                    return Wrap(
                      spacing: 9,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: narrow ? constraints.maxWidth : null,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _saving
                                ? const FilledButton(
                                    key: ValueKey('cash-float-saving'),
                                    onPressed: null,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _raspberry,
                                          ),
                                        ),
                                        SizedBox(width: 9),
                                        Text('Saving…'),
                                      ],
                                    ),
                                  )
                                : receive,
                          ),
                        ),
                        SizedBox(
                          width: narrow ? constraints.maxWidth : null,
                          child: report,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _cardShell(Widget child) => AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_raspberry, _darkRaspberry],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: _darkRaspberry.withValues(alpha: .22),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    ),
  );

  Widget _statusBadge(String status, bool isShort) {
    final label = switch (status) {
      'received' => 'Received',
      'reported' => isShort ? 'Shortfall' : 'Reported',
      _ => 'Awaiting',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _statusDetails(Map<String, dynamic> data, bool isShort) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      statusMessage(data, isShort),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    ),
  );

  String statusMessage(Map<String, dynamic> data, bool isShort) {
    if (data['status'] == 'received') {
      return 'Received by ${data['receivedByName'] ?? 'branch staff'}';
    }
    if (isShort) {
      return 'Short by ${_money(data['shortfallAmount'])} · ${_money(data['receivedAmount'])} added to the branch cash drawer.';
    }
    final reason = '${data['reportReason'] ?? 'Cash float reported'}';
    final note = '${data['reportMessage'] ?? ''}'.trim();
    return note.isEmpty ? reason : '$reason · $note';
  }

  Future<void> _confirmReceipt(
    Map<String, dynamic> data,
    dynamic amount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm cash received?'),
        content: Text(
          'Confirm that ${_money(amount)} was received for ${data['branchName'] ?? 'this branch'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm receipt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submit(
      () async {
        final actor = await resolveSessionActor(
          _firestore,
          admin: widget.role.toLowerCase() == 'admin',
        );
        await CashFloatService.receive(
          firestore: _firestore,
          requestId: widget.requestId,
          actorId: actor.id,
          actorName: actor.name,
          actorRole: widget.role,
          chatId: widget.chatId,
          messageActorId: actor.publicId.isEmpty ? actor.id : actor.publicId,
        );
      },
      success: 'Receipt confirmed. The branch cash drawer was updated.',
      failure: 'Unable to confirm receipt',
    );
  }

  Future<void> _report(Map<String, dynamic> data, dynamic amount) async {
    final report =
        await showDialog<({String reason, String note, double shortfall})>(
          context: context,
          builder: (_) => _CashFloatReportDialog(
            amount: amount,
            branchName: '${data['branchName'] ?? 'this branch'}',
          ),
        );
    if (report == null || !mounted) return;
    if (report.reason == 'Amount is short' &&
        (report.shortfall <= 0 ||
            report.shortfall >= (amount is num ? amount.toDouble() : 0))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a shortfall greater than zero and below the allocated amount.',
          ),
        ),
      );
      return;
    }
    await _submit(
      () async {
        final actor = await resolveSessionActor(
          _firestore,
          admin: widget.role.toLowerCase() == 'admin',
        );
        await CashFloatService.reportNotReceived(
          firestore: _firestore,
          requestId: widget.requestId,
          actorId: actor.id,
          actorName: actor.name,
          actorRole: widget.role,
          reason: report.reason,
          message: report.note,
          shortfallAmount: report.shortfall,
          chatId: widget.chatId,
          messageActorId: actor.publicId.isEmpty ? actor.id : actor.publicId,
        );
      },
      success: report.reason == 'Amount is short'
          ? 'Report sent. The received amount was added to the branch cash drawer.'
          : 'Cash float report sent to Super Admin.',
      failure: 'Unable to send report',
    );
  }

  Future<void> _submit(
    Future<void> Function() action, {
    required String success,
    required String failure,
  }) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$failure: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CashFloatReportDialog extends StatefulWidget {
  const _CashFloatReportDialog({
    required this.amount,
    required this.branchName,
  });

  final dynamic amount;
  final String branchName;

  @override
  State<_CashFloatReportDialog> createState() => _CashFloatReportDialogState();
}

class _CashFloatReportDialogState extends State<_CashFloatReportDialog> {
  final _shortfallController = TextEditingController();
  final _noteController = TextEditingController();
  String _reason = 'Cash did not arrive';

  @override
  void dispose() {
    _shortfallController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Report cash float'),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Allocated ${formatMoney(widget.amount is num ? widget.amount : double.tryParse('${widget.amount}') ?? 0)} for ${widget.branchName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: const [
                DropdownMenuItem(
                  value: 'Cash did not arrive',
                  child: Text('Cash did not arrive'),
                ),
                DropdownMenuItem(
                  value: 'Amount is short',
                  child: Text('Amount is short'),
                ),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _reason = value);
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _reason == 'Amount is short'
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: _shortfallController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount missing',
                          prefixText: '₱ ',
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message to Super Admin (optional)',
                alignLabelWithHint: true,
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
          onPressed: () {
            final missing =
                double.tryParse(_shortfallController.text.trim()) ?? 0;
            Navigator.pop(context, (
              reason: _reason,
              note: _noteController.text.trim(),
              shortfall: missing,
            ));
          },
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
