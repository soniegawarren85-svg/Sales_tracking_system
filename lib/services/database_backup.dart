import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseBackup {
  static const collections = [
    '_metadata',
    'admin_notifications',
    'admin_settings',
    'allocation_checklist',
    'mail',
    'password_reset_otps',
    'branches',
    'budget_history',
    'coffee_flavors',
    'coffee_addons',
    'coffee_products',
    'completed_sales',
    'counters',
    'daily_reports',
    'inventory_reports',
    'messages',
    'pending_order_history',
    'pending_orders',
    'sales_inventory',
    'staff_budget',
    'staff_cash_drawer',
    'staff_inventory',
    'staff_inventory_history',
    'staff_login_sessions',
    'staff_requests',
    'stock_adjustments',
    'system_counters',
  ];
  static dynamic encode(dynamic value) {
    if (value is DateTime) return encode(Timestamp.fromDate(value));
    if (value is double && !value.isFinite)
      return {'__type': 'double', 'value': value.toString()};
    if (value is Timestamp)
      return {
        '__type': 'timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
      };
    if (value is GeoPoint)
      return {
        '__type': 'geopoint',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    if (value is DocumentReference)
      return {'__type': 'reference', 'path': value.path};
    if (value is Blob)
      return {'__type': 'blob', 'data': base64Encode(value.bytes)};
    if (value is Map)
      return value.map((k, v) => MapEntry(k.toString(), encode(v)));
    if (value is List) return value.map(encode).toList();
    return value;
  }

  static dynamic decode(dynamic value) {
    if (value is List) return value.map(decode).toList();
    if (value is Map) {
      switch (value['__type']) {
        case 'double':
          return double.parse(value['value'] as String);
        case 'timestamp':
          return Timestamp(
            value['seconds'] as int,
            value['nanoseconds'] as int,
          );
        case 'geopoint':
          return GeoPoint(
            (value['latitude'] as num).toDouble(),
            (value['longitude'] as num).toDouble(),
          );
        case 'reference':
          return FirebaseFirestore.instance.doc(value['path'] as String);
        case 'blob':
          return Blob(base64Decode(value['data'] as String));
      }
      return value.map((k, v) => MapEntry(k.toString(), decode(v)));
    }
    return value;
  }

  static Future<Uint8List> export({FirebaseFirestore? firestore}) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final records = <String, dynamic>{};
    for (final name in collections) {
      try {
        final snapshot = await db
            .collection(name)
            .get(const GetOptions(source: Source.server));
        for (final doc in snapshot.docs) {
          records[doc.reference.path] = encode(doc.data());
          if (name == 'messages') {
            final messages = await doc.reference
                .collection('items')
                .get(const GetOptions(source: Source.server));
            for (final message in messages.docs)
              records[message.reference.path] = encode(message.data());
          }
        }
      } on FirebaseException catch (error) {
        throw StateError(
          'Backup could not read $name (${error.code}): ${error.message ?? 'Firebase rejected the request'}. No incomplete backup was downloaded.',
        );
      }
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'sales-tracking-backup',
          'version': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'documentCount': records.length,
          'documents': records,
        }),
      ),
    );
  }

  static Map<String, Map<String, dynamic>> validate(Uint8List bytes) {
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['format'] != 'sales-tracking-backup' ||
        data['version'] != 1 ||
        data['documents'] is! Map)
      throw const FormatException('Invalid backup file');
    final result = <String, Map<String, dynamic>>{};
    for (final entry in (data['documents'] as Map).entries) {
      final path = entry.key.toString();
      final parts = path.split('/');
      if (!(parts.length == 2 ||
              (parts.length == 4 &&
                  parts.first == 'messages' &&
                  parts[2] == 'items')) ||
          !collections.contains(parts.first) ||
          parts.last.isEmpty ||
          entry.value is! Map)
        throw FormatException('Invalid document: $path');
      result[path] = Map<String, dynamic>.from(decode(entry.value) as Map);
    }
    return result;
  }

  static Future<void> restore(
    Map<String, Map<String, dynamic>> records, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final entries = records.entries.toList();
    for (var offset = 0; offset < entries.length; offset += 20) {
      final batch = db.batch();
      for (final entry in entries.skip(offset).take(20)) {
        batch.set(db.doc(entry.key), entry.value);
      }
      await batch.commit();
    }
  }
}
