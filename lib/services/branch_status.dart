bool isActiveBranch(Map<String, dynamic> branch) {
  final status = '${branch['status'] ?? ''}'.trim().toLowerCase();
  return branch['isVoided'] != true &&
      branch['isDeleted'] != true &&
      branch['isDeactivated'] != true &&
      branch['deletedAt'] == null &&
      branch['voidedAt'] == null &&
      branch['deactivatedAt'] == null &&
      !{
        'inactive',
        'deactivated',
        'deleted',
        'void',
        'voided',
        'removed',
      }.contains(status);
}

bool isVisibleInBranchPerformance(Map<String, dynamic> branch) =>
    branch['isVoided'] != true;
