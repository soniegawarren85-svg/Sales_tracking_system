import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_database_sync_service.dart';

/// Public staff codes are display IDs. Older allocations can still use the
/// four-digit spelling, while branch membership normally uses the auth UID.
Set<String> staffIdentityKeys(String uid, Map<String, dynamic> profile) {
  final keys = <String>{uid};
  for (final field in ['staffId', 'publicId']) {
    final value = profile[field]?.toString().trim() ?? '';
    if (value.isEmpty) continue;
    keys.add(value);
    final match = RegExp(
      r'^STF-0*(\d+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) {
      final number = int.parse(match[1]!).toString();
      keys.add('STF-${number.padLeft(3, '0')}');
      keys.add('STF-${number.padLeft(4, '0')}');
    }
  }
  return keys.where((key) => key.isNotEmpty).toSet();
}

List<String> staffAllocationTargets(
  String uid,
  Map<String, dynamic> profile,
  Iterable<String> branches,
) => <String>{
  ...branches.where((id) => id.isNotEmpty),
  ...staffIdentityKeys(uid, profile),
}.toList();

bool allocationBelongsTo(
  Map<String, dynamic> record,
  Iterable<String> targets,
) => targets.contains(record['staffId']?.toString());

class StaffAllocationScope {
  const StaffAllocationScope(this.targets, this.profile);
  final List<String> targets;
  final Map<String, dynamic> profile;
}

/// Keeps listening after empty cache snapshots, delayed internet, and changes
/// made by the admin. One failed branch query never disables direct staff stock.
Stream<StaffAllocationScope> watchStaffAllocationScope(
  String uid, {
  FirebaseFirestore? firestore,
  SharedPreferences? preferences,
  Future<List<Map<String, dynamic>>> Function()? readCachedProfiles,
}) {
  final db = firestore ?? FirebaseFirestore.instance;
  late StreamController<StaffAllocationScope> controller;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? branchSub;
  var stopped = false;
  var profile = <String, dynamic>{};
  var savedBranches = <String>[];
  var queriedBranches = <String>[];
  var profileBranches = <String>[];
  var branchQueryKey = '';
  var branchServerSeen = false;
  var profileServerSeen = false;
  SharedPreferences? prefs;

  void emit() {
    if (stopped) return;
    final branches = <String>{
      if (!branchServerSeen || !profileServerSeen) ...savedBranches,
      ...profileBranches,
      ...queriedBranches,
    }.toList();
    controller.add(
      StaffAllocationScope(
        staffAllocationTargets(uid, profile, branches),
        profile,
      ),
    );
    if (branchServerSeen && profileServerSeen) {
      savedBranches = branches;
      unawaited(prefs!.setStringList('staffBranchIds.$uid', branches));
    }
  }

  void listenBranches() {
    final identities = staffIdentityKeys(uid, profile).toList()..sort();
    final key = identities.join('|');
    if (key == branchQueryKey) return;
    branchQueryKey = key;
    branchServerSeen = false;
    unawaited(branchSub?.cancel());
    branchSub = db
        .collection('branches')
        .where('staffIds', arrayContainsAny: identities)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (stopped || branchQueryKey != key) return;
            // An empty offline SDK cache is not proof that assignments were removed.
            if (!snapshot.metadata.isFromCache || snapshot.docs.isNotEmpty) {
              queriedBranches = snapshot.docs
                  .where((doc) => doc.data()['isDeleted'] != true)
                  .map((doc) => doc.id)
                  .toList();
            }
            if (!snapshot.metadata.isFromCache) branchServerSeen = true;
            emit();
          },
          onError: (Object error) {
            debugPrint('Branch assignment listener: $error');
            emit();
          },
        );
  }

  Future<void> start() async {
    prefs = preferences ?? await SharedPreferences.getInstance();
    final cached =
        await (readCachedProfiles?.call() ??
            LocalDatabaseSyncService().getCachedCollection('staff_requests'));
    for (final row in cached) {
      if (row['_localDocId'] == uid ||
          row['uid'] == uid ||
          row['userId'] == uid) {
        profile = row;
        break;
      }
    }
    profile['staffId'] ??= prefs!.getString('staffPublicId.$uid');
    savedBranches = prefs!.getStringList('staffBranchIds.$uid') ?? [];
    final savedUid =
        prefs!.getString('lastStaffDocId') ?? prefs!.getString('lastUserId');
    if (savedBranches.isEmpty && savedUid == uid)
      savedBranches = prefs!.getStringList('lastStaffBranchIds') ?? [];
    profileBranches = (profile['branchIds'] as List? ?? [])
        .map((id) => id.toString())
        .toList();
    if (stopped) return;
    emit();
    listenBranches();
    profileSub = db
        .collection('staff_requests')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (stopped) return;
            if (snapshot.exists) {
              profile = snapshot.data()!;
              if (profile['staffId'] != null)
                unawaited(
                  prefs!.setString(
                    'staffPublicId.$uid',
                    profile['staffId'].toString(),
                  ),
                );
              profileBranches = (profile['branchIds'] as List? ?? [])
                  .map((id) => id.toString())
                  .toList();
              // Persist this profile separately from the admin's broader cache.
              unawaited(
                prefs!.setStringList(
                  'staffBranchIds.$uid',
                  <String>{...savedBranches, ...profileBranches}.toList(),
                ),
              );
              listenBranches();
            }
            if (!snapshot.metadata.isFromCache) profileServerSeen = true;
            emit();
          },
          onError: (Object error) {
            debugPrint('Staff assignment listener: $error');
            emit();
          },
        );
  }

  controller = StreamController<StaffAllocationScope>(
    onListen: () {
      unawaited(
        start().catchError((Object error, StackTrace stack) {
          if (!stopped) controller.addError(error, stack);
        }),
      );
    },
    onCancel: () async {
      stopped = true;
      await profileSub?.cancel();
      await branchSub?.cancel();
    },
  );
  return controller.stream;
}
