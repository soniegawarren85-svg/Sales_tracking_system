import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/branch_permissions.dart';

class BranchPermissionGate extends StatelessWidget {
  const BranchPermissionGate({super.key, required this.permission, required this.child, this.database});
  final String permission;
  final Widget child;
  final FirebaseFirestore? database;
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream: (database ?? FirebaseFirestore.instance).collection('admin_settings').doc('transactions').snapshots(),
    builder: (context, settings) => FutureBuilder<bool>(
      future: BranchPermissions.allowed(permission, database: database),
      builder: (context, allowed) => allowed.data == true ? child : const SizedBox.shrink(),
    ),
  );
}
