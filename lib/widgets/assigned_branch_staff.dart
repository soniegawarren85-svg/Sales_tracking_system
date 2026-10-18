import 'package:flutter/material.dart';
import 'staff_performance_panel.dart';

Future<void> showAssignedBranchStaff(BuildContext context, String branchId, {bool roleSelection = false}) =>
    showDialog<void>(
      context: context,
      builder: (_) => StaffPerformancePanel(branchId: branchId, roleSelection: roleSelection),
    );
