import 'package:cloud_firestore/cloud_firestore.dart';

class LocalDatabaseSyncService {
  LocalDatabaseSyncService._();

  static final LocalDatabaseSyncService _instance =
      LocalDatabaseSyncService._();

  factory LocalDatabaseSyncService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void start() {}

  Future<List<Map<String, dynamic>>> getCachedCollection(
    String collection,
  ) async {
    final snapshot = await _firestore.collection(collection).limit(1000).get();
    return snapshot.docs
        .map((doc) => {...doc.data(), '_localDocId': doc.id})
        .toList();
  }

  Future<void> cacheCollectionDocs(
    String collection,
    Iterable<Map<String, dynamic>> docs,
  ) async {}

  Future<void> refreshCoreCollectionsFromFirebase() async {}

  Stream<List<Map<String, dynamic>>> watchLocalCompletedSales() {
    return Stream<List<Map<String, dynamic>>>.value(const []);
  }

  Future<void> recordCompletedSale(Map<String, dynamic> payload) async {
    final now = DateTime.now();
    final salesId = payload['salesId']?.toString().trim();
    final docId = salesId?.isNotEmpty == true
        ? salesId!
        : _firestore.collection('completed_sales').doc().id;
    final cloudPayload = Map<String, dynamic>.from(payload);
    cloudPayload.remove('localOnly');
    cloudPayload['localId'] = docId;
    cloudPayload['syncedAt'] = FieldValue.serverTimestamp();

    final timestamp = cloudPayload['timestamp'];
    if (timestamp is String) {
      final parsed = DateTime.tryParse(timestamp);
      cloudPayload['timestamp'] = parsed == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(parsed);
    } else if (timestamp is DateTime) {
      cloudPayload['timestamp'] = Timestamp.fromDate(timestamp);
    } else if (timestamp is! Timestamp) {
      cloudPayload['timestamp'] = Timestamp.fromDate(now);
    }

    await _firestore
        .collection('completed_sales')
        .doc(docId)
        .set(cloudPayload, SetOptions(merge: true));
  }

  Future<void> syncPendingSales() async {}

  void dispose() {}
}
