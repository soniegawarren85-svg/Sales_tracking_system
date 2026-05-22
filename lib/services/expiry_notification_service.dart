import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ExpiryNotificationService {
  ExpiryNotificationService._internal();

  static final ExpiryNotificationService _instance =
      ExpiryNotificationService._internal();

  factory ExpiryNotificationService() => _instance;

  final _firestore = FirebaseFirestore.instance;

  int _getDaysUntilExpiry(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.difference(today).inDays;
    } catch (e) {
      return 999;
    }
  }

  bool _isExpiringSoon(String expirationDate) {
    final daysLeft = _getDaysUntilExpiry(expirationDate);
    return daysLeft > 0 && daysLeft <= 3;
  }

  bool _isExpired(String expirationDate) {
    try {
      final expiryDate = DateTime.parse(expirationDate);
      final today = DateTime.now();
      return expiryDate.isBefore(
        DateTime(today.year, today.month, today.day + 1),
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasExistingExpirationNotification(
    List<String> variantIds,
    String notificationType,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('admin_notifications')
          .where('type', isEqualTo: notificationType)
          .get();

      if (snapshot.docs.isEmpty) {
        return false;
      }

      final currentIds = variantIds.toSet();
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final existingIds = ((data['itemIds'] as List<dynamic>?) ?? [])
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toSet();

        if (existingIds.containsAll(currentIds)) {
          debugPrint('Found existing notification for $notificationType');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking existing notification: $e');
      return false;
    }
  }

  Future<void> checkAndNotifyExpiringItems() async {
    try {
      final snapshot = await _firestore.collection('sales_inventory').get();
      final expiringItems = <Map<String, dynamic>>[];
      final expiredItems = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;

        final categoryName = data['name']?.toString() ?? '';
        final items = (data['items'] as List<dynamic>?) ?? [];

        for (var item in items) {
          final itemData = item as Map<String, dynamic>;
          final expiryDate = itemData['expirationDate']?.toString() ?? '';
          final daysLeft = _getDaysUntilExpiry(expiryDate);

          if (_isExpiringSoon(expiryDate)) {
            expiringItems.add({
              'categoryName': categoryName,
              'itemName': itemData['name']?.toString() ?? '',
              'variantId': itemData['id']?.toString() ?? '',
              'daysLeft': daysLeft,
              'expiryDate': expiryDate,
            });
          } else if (_isExpired(expiryDate)) {
            expiredItems.add({
              'categoryName': categoryName,
              'itemName': itemData['name']?.toString() ?? '',
              'variantId': itemData['id']?.toString() ?? '',
              'expiryDate': expiryDate,
            });
          }
        }
      }

      if (expiringItems.isNotEmpty) {
        await _addExpirationNotification(
          expiringItems,
          'expiration_warning',
          '⚠️ Items Expiring Soon',
          'The following items are expiring within 3 days:\n\n',
        );
      }

      if (expiredItems.isNotEmpty) {
        await _addExpirationNotification(
          expiredItems,
          'item_expired',
          '🚨 Items Have Expired',
          'The following items have already expired:\n\n',
        );
      }
    } catch (e) {
      debugPrint('Error checking expiring items: $e');
    }
  }

  Future<void> _addExpirationNotification(
    List<Map<String, dynamic>> items,
    String notificationType,
    String title,
    String messagePrefix,
  ) async {
    try {
      final variantIds = items
          .map((item) => item['variantId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      debugPrint(
        'Checking for existing $notificationType with ${variantIds.length} items',
      );

      if (variantIds.isNotEmpty &&
          await _hasExistingExpirationNotification(
            variantIds,
            notificationType,
          )) {
        debugPrint('Notification already exists for today, skipping.');
        return;
      }

      final itemNames = items
          .map((item) {
            if (notificationType == 'expiration_warning') {
              return '${item['itemName']} (${item['categoryName']}) - ${item['daysLeft']} days';
            } else {
              return '${item['itemName']} (${item['categoryName']})';
            }
          })
          .join('\n');

      final notificationData = {
        'type': notificationType,
        'title': title,
        'message': '$messagePrefix$itemNames',
        'createdAt': Timestamp.now(),
        'dateCreated': DateTime.now(),
        'isRead': false,
        'itemCount': items.length,
        'itemIds': variantIds,
      };

      final docRef = await _firestore
          .collection('admin_notifications')
          .add(notificationData);

      debugPrint(
        '✅ $notificationType notification created: ${docRef.id} for ${items.length} items',
      );
    } catch (e) {
      debugPrint('❌ Error adding $notificationType notification: $e');
    }
  }
}
