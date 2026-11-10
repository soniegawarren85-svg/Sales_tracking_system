/// Legacy values remain readable; all new checklist writes use these labels.
class ChecklistStatus {
  static const awaiting = 'Awaiting Confirmation';
  static const received = 'Received';
  static const awaitingAdmin = 'Awaiting Admin Confirmation';
  static const awaitingSuperAdmin = 'Awaiting Super Admin Confirmation';
  static const completed = 'Return Completed';
  static const returnDeclined = 'Return Declined';
  static const issue = 'Issue Reported';
  static const discrepancy = 'Discrepancy Reported';
  static const notReceivedPending = 'Not Received - Pending Super Admin';
  static const notReceivedRestored = 'Not Received - Stock Restored';

  static String label(Map<String, dynamic> data) {
    final rawStatus = '${data['status'] ?? ''}'.trim();
    final normalized = rawStatus
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (normalized == 'pending') return awaiting;
    if (normalized == 'accepted') return received;
    if (normalized == 'declined') return 'Declined (stock restored)';
    if (normalized == 'awaiting super admin' ||
        normalized == 'awaiting superadmin confirmation' ||
        normalized == 'awaiting super admin confirmation') {
      return awaitingSuperAdmin;
    }
    if (normalized == 'awaiting admin' ||
        normalized == 'awaiting admin confirmation') {
      return awaitingAdmin;
    }
    if (normalized == 'return completed' || normalized == 'completed') {
      return completed;
    }
    if (normalized == 'return declined' || normalized == 'rejected') {
      return returnDeclined;
    }
    return rawStatus.isEmpty ? 'Unknown' : rawStatus;
  }

  static bool isReturnRecord(Map<String, dynamic> data) {
    final kind = '${data['kind'] ?? ''}'.trim().toLowerCase();
    return kind == 'return' ||
        kind.startsWith('return_') ||
        ('${data['returnSourceCollection'] ?? ''}'.trim().isNotEmpty &&
            '${data['returnSourceId'] ?? ''}'.trim().isNotEmpty) ||
        (data['forwardedAt'] != null && data['forwardedBy'] != null);
  }

  static bool incomingOpen(Map<String, dynamic> data) =>
      data['kind'] != 'return' && [awaiting, issue].contains(label(data));

  static bool allocationNeedsSuperAdminReview(Map<String, dynamic> data) =>
      data['kind'] == 'not_received' && label(data) == notReceivedPending;

  static bool returnOpen(Map<String, dynamic> data) =>
      isReturnRecord(data) &&
      [awaitingAdmin, awaitingSuperAdmin, discrepancy].contains(label(data));

  static bool returnPendingForAdmin(Map<String, dynamic> data) =>
      isReturnRecord(data) &&
      [awaitingAdmin, discrepancy].contains(label(data));

  static bool returnPendingForSuperAdmin(Map<String, dynamic> data) {
    if (!isReturnRecord(data)) return false;
    final status = label(data);
    if ([completed, returnDeclined].contains(status)) return false;
    return [awaitingAdmin, awaitingSuperAdmin, discrepancy].contains(status) ||
        (data['forwardedAt'] != null && data['forwardedBy'] != null);
  }

  static bool pending(Map<String, dynamic> data, {required bool admin}) =>
      admin ? returnPendingForAdmin(data) : incomingOpen(data);
}
