import 'package:cloud_firestore/cloud_firestore.dart';
import 'allocation_checklist_service.dart';
import 'checklist_status.dart';
import 'inventory_display_ids.dart';

String returnText(
  Iterable<dynamic> values, [
  String fallback = 'Not recorded',
]) => values
    .map((v) => '${v ?? ''}'.trim())
    .firstWhere((v) => v.isNotEmpty, orElse: () => fallback);

String returnItemName(Map item) => returnText([
  item['flavor'],
  item['variant'],
  item['itemName'],
  item['name'],
  item['categoryName'],
], 'Item');

String returnItemCode(Map item) => inventoryDisplayId({
  for (final key in [
    'publicId',
    'itemPublicId',
    'coffeeId',
    'bundleId',
    'addonId',
    'itemId',
    'variantId',
    'id',
  ])
    if ('${item[key] ?? ''}'.trim().isNotEmpty)
      key == 'itemPublicId' ? 'publicId' : key: item[key],
});

/// One atomic commit per submission. All source claims are checked before writes,
/// and the same batch ID makes retries safe after an uncertain network response.
class ReturnBatchService {
  ReturnBatchService(this.db);
  final FirebaseFirestore db;

  Future<int> submit({
    required String batchId,
    required List<Map<String, dynamic>> items,
    required String actorId,
    required String actorName,
    required String actorPublicId,
    required List<String> scopeIds,
  }) async {
    if (batchId.isEmpty ||
        actorId.isEmpty ||
        items.isEmpty ||
        items.length > 200) {
      throw ArgumentError(
        'Sign in and select between 1 and 200 return records.',
      );
    }
    final keys = <String>{};
    for (final item in items) {
      if (![
            'completed_sales',
            'stock_adjustments',
          ].contains(item['collection']) ||
          '${item['id'] ?? ''}'.isEmpty ||
          '${item['line'] ?? ''}'.isEmpty ||
          !scopeIds.contains(item['branchId']) ||
          AllocationChecklistService.quantity(item['quantity']) <= 0 ||
          !keys.add('${item['collection']}/${item['id']}/${item['line']}')) {
        throw ArgumentError(
          'Select valid, distinct refund/reduce records and their original branch.',
        );
      }
    }
    return db.runTransaction(
      (tx) async {
        final returnRefs = [
          for (var i = 0; i < items.length; i++)
            db.collection('allocation_checklist').doc('${batchId}_$i'),
        ];
        final existing = await Future.wait(
          returnRefs.map((ref) => tx.get(ref)),
        );
        if (existing.every((doc) => doc.exists)) {
          for (var i = 0; i < items.length; i++) {
            final data = existing[i].data()!;
            if (data['batchSize'] != items.length ||
                data['submittedBy'] != actorId ||
                data['returnSourceId'] != items[i]['id'] ||
                data['returnSourceCollection'] != items[i]['collection'] ||
                data['returnLineKey'] != items[i]['line'] ||
                data['quantity'] != items[i]['quantity'] ||
                data['branchId'] != items[i]['branchId']) {
              throw StateError(
                'This batch ID belongs to a different submission.',
              );
            }
          }
          return 0;
        }
        if (existing.any((doc) => doc.exists))
          throw StateError(
            'Incomplete batch record. Refresh the checklist before retrying.',
          );
        final sourcePaths = items
            .map((item) => '${item['collection']}/${item['id']}')
            .toSet();
        final sources = await Future.wait(
          sourcePaths.map((path) => tx.get(db.doc(path))),
        );
        final sourceData = {
          for (final doc in sources) doc.reference.path: doc.data(),
        };
        final stockPaths = sources
            .where(
              (doc) =>
                  doc.reference.parent.id == 'stock_adjustments' &&
                  doc.data()?['branchId'] == null,
            )
            .map((doc) => '${doc.data()?['categoryId'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toSet();
        final stocks = await Future.wait(
          stockPaths.map(
            (id) => tx.get(db.collection('staff_inventory').doc(id)),
          ),
        );
        final stockData = {for (final doc in stocks) doc.id: doc.data()};
        final claims = <String, Map<String, dynamic>>{};
        final records = <Map<String, dynamic>>[];
        for (final selected in items) {
          final path = '${selected['collection']}/${selected['id']}';
          final data = sourceData[path];
          if (data == null || data['isDeleted'] == true)
            throw StateError(
              'A selected source is no longer available. Refresh the list.',
            );
          final owner = data['userId'] ?? data['staffId'];
          if (owner != actorId &&
              !scopeIds.contains(owner) &&
              !scopeIds.contains(data['branchId'])) {
            throw StateError(
              'A selected record is outside your assigned branch.',
            );
          }
          final stock = stockData['${data['categoryId']}'];
          final savedBranch = data['branchId'] ?? stock?['staffId'];
          if (savedBranch != null &&
              savedBranch != actorId &&
              savedBranch != selected['branchId']) {
            throw StateError('Return each item to its original branch.');
          }
          final refund = selected['collection'] == 'completed_sales';
          Map<String, dynamic> item;
          if (refund) {
            if (![
              'refund',
              'refunded',
            ].contains('${data['type'] ?? data['status']}'.toLowerCase()))
              throw StateError('Select a recorded refund.');
            final lines = AllocationChecklistService.rows(data['items']);
            final index = int.tryParse('${selected['line']}') ?? -1;
            if (index < 0 || index >= lines.length)
              throw StateError('Refund item no longer exists.');
            item = lines[index];
          } else {
            if (data['type'] == 'addon_void' || selected['line'] != 'item')
              throw StateError('Select a recorded physical reduction.');
            item = data;
          }
          final claimed = claims.putIfAbsent(
            path,
            () => Map<String, dynamic>.from(
              data['checklistReturnedQuantities'] as Map? ?? {},
            ),
          );
          final line = '${selected['line']}';
          final count = AllocationChecklistService.quantity(
            selected['quantity'],
          );
          final available =
              AllocationChecklistService.quantity(item['quantity']) -
              AllocationChecklistService.quantity(claimed[line]);
          if (count > available)
            throw StateError(
              '${returnItemName(item)} has only $available unsubmitted items. Refresh the list.',
            );
          claimed[line] =
              AllocationChecklistService.quantity(claimed[line]) + count;
          final sourceType = '${data['type'] ?? ''}';
          final reason = returnText([
            item['refundReason'],
            data['reason'],
            data['refundReason'],
            data['reductionReason'],
          ]);
          records.add({
            'schemaVersion': 3,
            'kind': 'return',
            'batchId': batchId,
            'batchSize': items.length,
            'status': ChecklistStatus.awaitingAdmin,
            'staffId': selected['branchId'],
            'branchId': selected['branchId'],
            'branchName': selected['branchName'],
            'submittedBy': actorId,
            'submittedByName': actorName,
            'submittedByStaffId': actorPublicId,
            'staffName': actorName,
            'name': returnItemName(item),
            'itemDisplayId': returnText([
              selected['itemDisplayId'],
            ], returnItemCode(item)),
            'quantity': count,
            'reason': reason,
            'originalReason': reason,
            'comment': returnText([
              item['comment'],
              data['comment'],
              data['details'],
            ], ''),
            'sourceItem': item,
            'expirationDate':
                item['expirationDate'] ??
                data['expirationDate'] ??
                selected['expirationDate'],
            'sourceStaffUid': data['userId'] ?? data['staffId'],
            'sourceDate': data['timestamp'] ?? data['createdAt'],
            'sourceStaffName': returnText([
              selected['staffName'],
              data['staffName'],
              data['staffFullName'],
            ], actorName),
            'sourceStaffId': returnText([
              data['staffPublicId'],
              selected['staffPublicId'],
            ], actorPublicId),
            'sourceReceiptId': data['salesId'] ?? data['receiptId'],
            'unitPrice':
                item['price'] ?? item['unitPrice'] ?? data['unitPrice'],
            'returnSourceCollection': selected['collection'],
            'returnSourceId': selected['id'],
            'returnLineKey': line,
            'isBundle':
                item['isBundle'] == true ||
                data['isBundle'] == true ||
                stock?['isBundle'] == true ||
                selected['isBundle'] == true ||
                sourceType.contains('bundle'),
            'isCoffee':
                item['isCoffee'] == true ||
                data['isCoffee'] == true ||
                stock?['isCoffee'] == true ||
                selected['isCoffee'] == true ||
                sourceType.contains('coffee'),
            'isAddon':
                item['isAddon'] == true ||
                data['isAddon'] == true ||
                selected['isAddon'] == true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        for (final entry in claims.entries) {
          tx.update(db.doc(entry.key), {
            'checklistReturnedQuantities': entry.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        for (var i = 0; i < records.length; i++) {
          tx.set(returnRefs[i], records[i]);
        }
        return records.length;
      },
      timeout: const Duration(seconds: 15),
      maxAttempts: 2,
    );
  }
}
