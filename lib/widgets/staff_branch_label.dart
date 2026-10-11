import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StaffBranchLabel extends StatefulWidget {
  final List<String> branchIds;
  final List<String> staffIdentifiers;
  final FirebaseFirestore? firestore;

  const StaffBranchLabel({
    super.key,
    required this.branchIds,
    required this.staffIdentifiers,
    this.firestore,
  });

  @override
  State<StaffBranchLabel> createState() => _StaffBranchLabelState();
}

class _StaffBranchLabelState extends State<StaffBranchLabel> {
  late Future<List<String>> _branchNames;

  @override
  void initState() {
    super.initState();
    _branchNames = _loadBranchNames();
  }

  @override
  void didUpdateWidget(covariant StaffBranchLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchIds.join('|') != widget.branchIds.join('|') ||
        oldWidget.staffIdentifiers.join('|') !=
            widget.staffIdentifiers.join('|')) {
      _branchNames = _loadBranchNames();
    }
  }

  Future<List<String>> _loadBranchNames() async {
    final firestore = widget.firestore ?? FirebaseFirestore.instance;
    final names = <String, String>{};
    final branchReads = widget.branchIds
        .toSet()
        .take(10)
        .map((id) => firestore.collection('branches').doc(id).get());
    for (final branch in await Future.wait(branchReads)) {
      final name = branch.data()?['name']?.toString().trim() ?? '';
      if (branch.exists && name.isNotEmpty) names[branch.id] = name;
    }

    final identifiers = widget.staffIdentifiers.toSet().take(30).toList();
    if (identifiers.isNotEmpty) {
      final assigned = await firestore
          .collection('branches')
          .where('staffIds', arrayContainsAny: identifiers)
          .get();
      for (final branch in assigned.docs) {
        final name = branch.data()['name']?.toString().trim() ?? '';
        if (branch.data()['isDeleted'] != true && name.isNotEmpty) {
          names[branch.id] = name;
        }
      }
    }
    return names.values.toList()..sort();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _branchNames,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Branch information unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFFFFD8B5),
            fontWeight: FontWeight.w500,
          ),
        );
      }
      final names = snapshot.data ?? const <String>[];
      if (names.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          'Branch: ${names.join(', ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFFFFD8B5),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      );
    },
  );
}
