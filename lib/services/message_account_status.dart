bool isMessageAccountAvailable(Map<String, dynamic> account) {
  final status = '${account['status'] ?? ''}'
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ');
  return account['isDeleted'] != true &&
      account['isVoided'] != true &&
      account['isDeactivated'] != true &&
      account['isSuspended'] != true &&
      account['isDisabled'] != true &&
      !{
        'deleted',
        'voided',
        'rejected',
        'deactivated',
        'suspended',
        'disabled',
        'inactive',
        'blocked',
      }.contains(status);
}
