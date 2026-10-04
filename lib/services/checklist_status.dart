/// Legacy values remain readable; all new checklist writes use these labels.
class ChecklistStatus {
  static const awaiting = 'Awaiting Confirmation';
  static const received = 'Received';
  static const awaitingAdmin = 'Awaiting Admin Confirmation';
  static const completed = 'Return Completed';
  static const returnDeclined = 'Return Declined';
  static const issue = 'Issue Reported';
  static const discrepancy = 'Discrepancy Reported';

  static String label(Map<String, dynamic> data) => switch (data['status']) {
    'pending' => awaiting,
    'accepted' => received,
    'declined' => 'Declined (stock restored)',
    final String status => status,
    _ => 'Unknown',
  };

  static bool incomingOpen(Map<String, dynamic> data) =>
      data['kind'] != 'return' && [awaiting, issue].contains(label(data));

  static bool returnOpen(Map<String, dynamic> data) =>
      data['kind'] == 'return' &&
      [awaitingAdmin, discrepancy].contains(label(data));

  static bool pending(Map<String, dynamic> data, {required bool admin}) =>
      admin ? returnOpen(data) : incomingOpen(data);
}
