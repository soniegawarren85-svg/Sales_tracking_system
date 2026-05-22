import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  bool _dialogOpen = false;

  Stream<QuerySnapshot> get _adminNotificationStream {
    try {
      return FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('createdAt', descending: true)
          .snapshots();
    } catch (e) {
      debugPrint('Error in notification stream: $e');
      return FirebaseFirestore.instance
          .collection('admin_notifications')
          .snapshots();
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('admin_notifications')
        .where('isRead', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> _markFirestoreNotificationRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('admin_notifications')
        .doc(docId)
        .update({'isRead': true});
  }

  Future<void> _deleteFirestoreNotification(String docId) async {
    final docRef = FirebaseFirestore.instance
        .collection('admin_notifications')
        .doc(docId);

    final snapshot = await docRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() as Map<String, dynamic>?;
    final isReport = data?['type']?.toString().trim().toLowerCase() == 'report';

    if (isReport) {
      final staffId = data?['staffId']?.toString() ?? '';
      final reportDate = data?['reportDate']?.toString();

      if (staffId.isNotEmpty && reportDate != null) {
        final existing = await FirebaseFirestore.instance
            .collection('daily_reports')
            .where('staffId', isEqualTo: staffId)
            .where('reportDate', isEqualTo: reportDate)
            .get();

        if (existing.docs.isEmpty) {
          final reportData = Map<String, dynamic>.from(data!);
          await FirebaseFirestore.instance
              .collection('daily_reports')
              .add(reportData);
        }
      }
    }

    await docRef.delete();
  }

  void _showNotificationDetail(Map<String, dynamic> data) {
    if (_dialogOpen) return;
    _dialogOpen = true;

    showDialog<void>(
      context: context,
      builder: (context) {
        final createdAt = data['createdAt'] as Timestamp?;
        final reportDate = data['reportDate'] as String?;
        final cashDrawerTotal = data['cashDrawerTotal'];
        final totalSales = data['totalSales'];
        final transactionCount = data['transactionCount'];
        final transactions = data['transactions'] as List<dynamic>?;

        return AlertDialog(
          title: Text(data['title']?.toString() ?? 'Notification Detail'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['message']?.toString() ?? ''),
                const SizedBox(height: 14),
                if (reportDate != null)
                  Text('Report date: ${reportDate.split('T').first}'),
                if (cashDrawerTotal != null)
                  Text('Cash drawer: ?${cashDrawerTotal.toString()}'),
                if (totalSales != null)
                  Text('Total sales: ?${totalSales.toString()}'),
                if (transactionCount != null)
                  Text('Transactions: ${transactionCount.toString()}'),
                if (createdAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Submitted: ${createdAt.toDate().toLocal()}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (transactions != null && transactions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Transaction details',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...transactions.take(5).map((transaction) {
                    final tx = transaction as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${tx['salesId'] ?? 'ID'} � ?${(tx['total'] ?? 0).toString()} at ${tx['timestamp'] ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7EEF2),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _adminNotificationStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text('Unable to load notifications'),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(docs),
                        const SizedBox(height: 8),
                        if (docs.isEmpty)
                          _buildEmptyState()
                        else
                          _buildNotificationList(docs),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<QueryDocumentSnapshot> docs) {
    final totalCount = docs.length;
    final unreadCount = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['isRead'] == false;
    }).length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B0038), Color(0xFFC2105C), Color(0xFFE91E63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.notifications_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Text(
                            'Notifications',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _markAllNotificationsRead,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 118),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.done_all_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Mark all read',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildHeaderStat(
                    label: 'Total',
                    value: totalCount.toString(),
                    icon: Icons.inbox_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildHeaderStat(
                    label: 'Unread',
                    value: unreadCount.toString(),
                    icon: Icons.mark_email_unread_rounded,
                    highlight: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat({
    required String label,
    required String value,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withOpacity(0.20)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(highlight ? 0.35 : 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.90),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<QueryDocumentSnapshot> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Recent'),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final docId = docs[index].id;
            return _buildFirestoreNotificationCard(index, data, docId);
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFFE91E63),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8B0038),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: const Color(0xFFF48FB1).withOpacity(0.4),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirestoreNotificationCard(
    int index,
    Map<String, dynamic> notif,
    String docId,
  ) {
    final bool isRead = notif['isRead'] == true;
    final String type = notif['type']?.toString() ?? 'general';
    final IconData iconData = type == 'report'
        ? Icons.assignment_rounded
        : Icons.notifications_rounded;
    final Color iconColor =
        type == 'report' ? const Color(0xFFE91E63) : const Color(0xFF8B0038);
    final Color iconBg = type == 'report'
        ? const Color(0xFFFCE4EC)
        : const Color(0xFFEDE7F6);

    return Dismissible(
      key: Key('$docId-$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.delete_rounded, color: Colors.white, size: 22),
            SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _deleteFirestoreNotification(docId),
      child: GestureDetector(
        onTap: () async {
          if (_dialogOpen) return;
          await _markFirestoreNotificationRead(docId);
          _showNotificationDetail(notif);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 14),
          height: 154,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isRead
                  ? Colors.transparent
                  : const Color(0xFFE91E63).withOpacity(0.20),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isRead
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFFE91E63).withOpacity(0.10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 104),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: isRead
                      ? Colors.white
                      : const Color(0xFFFCE4EC).withOpacity(0.45),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: iconColor.withOpacity(0.20),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        iconData,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  notif['title']?.toString() ?? 'Notification',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isRead
                                        ? FontWeight.w600
                                        : FontWeight.w800,
                                    color: const Color(0xFF8B0038),
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 9,
                                  height: 9,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE91E63),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE91E63).withOpacity(0.40),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            notif['message']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isRead
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isRead
                      ? const Color(0xFFFAFAFA)
                      : const Color(0xFFFCE4EC).withOpacity(0.30),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: isRead
                          ? Colors.grey.shade100
                          : const Color(0xFFE91E63).withOpacity(0.10),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        notif['category']?.toString() ?? 'General',
                        style: TextStyle(
                          fontSize: 10,
                          color: iconColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          notif['time']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.check_rounded,
                          size: 13,
                          color: isRead
                              ? const Color(0xFFE91E63)
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isRead ? 'Read' : 'Unread',
                          style: TextStyle(
                            fontSize: 10,
                            color: isRead
                                ? const Color(0xFFE91E63)
                                : Colors.grey.shade400,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE91E63).withOpacity(0.12),
                    const Color(0xFFF48FB1).withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                size: 44,
                color: const Color(0xFFE91E63).withOpacity(0.40),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8B0038),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No notifications at the moment.\nNew alerts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B0038), Color(0xFFE91E63)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Text(
                'Go to Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
