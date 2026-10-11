import 'package:flutter/material.dart';
import 'staff_performance_panel.dart';

Future<void> showAssignedBranchStaff(BuildContext context, String branchId) =>
    showDialog<void>(
      context: context,
      builder: (_) => StaffPerformancePanel(branchId: branchId),
    );
