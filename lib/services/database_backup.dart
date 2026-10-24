import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class BackupManifest {
  const BackupManifest({
    required this.backupId,
    required this.createdAt,
    required this.documentCount,
    required this.collectionCounts,
    required this.byteLength,
  });

  final String backupId;
  final DateTime createdAt;
  final int documentCount;
  final Map<String, int> collectionCounts;
  final int byteLength;
}

class DatabaseBackup {
  static const maxBackupBytes = 50 * 1024 * 1024;
  static const collections = [
    '_metadata',
    'admin_notifications',
    'admin_settings',
    'activity_logs',
    'allocation_checklist',
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
    if (value is double && !value.isFinite) {
      return {'__type': 'double', 'value': value.toString()};
    }
    if (value is Timestamp) {
      return {
        '__type': 'timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
      };
    }
    if (value is GeoPoint) {
      return {
        '__type': 'geopoint',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is DocumentReference) {
      return {'__type': 'reference', 'path': value.path};
    }
    if (value is Blob) {
      return {'__type': 'blob', 'data': base64Encode(value.bytes)};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), encode(v)));
    }
    if (value is List) return value.map(encode).toList();
    return value;
  }

  static bool _isSensitiveField(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('password') ||
        normalized.contains('credential') ||
        normalized.contains('secret') ||
        normalized.contains('apikey') ||
        normalized.contains('accesstoken') ||
        normalized.contains('refreshtoken') ||
        normalized.contains('resettoken') ||
        normalized == 'otp' ||
        normalized.endsWith('otp');
  }

  static dynamic _sanitize(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_isSensitiveField('${entry.key}'))
            '${entry.key}': _sanitize(entry.value),
      };
    }
    if (value is List) return value.map(_sanitize).toList();
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
          records[doc.reference.path] = encode(_sanitize(doc.data()));
          if (name == 'messages') {
            final messages = await doc.reference
                .collection('items')
                .get(const GetOptions(source: Source.server));
            for (final message in messages.docs) {
              records[message.reference.path] = encode(
                _sanitize(message.data()),
              );
            }
          }
        }
      } on FirebaseException catch (error) {
        throw StateError(
          'Backup could not read $name (${error.code}): ${error.message ?? 'Firebase rejected the request'}. No incomplete backup was downloaded.',
        );
      }
    }
    final createdAt = DateTime.now().toUtc();
    final counts = <String, int>{};
    for (final path in records.keys) {
      final collection = path.split('/').first;
      counts.update(collection, (total) => total + 1, ifAbsent: () => 1);
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'sales-tracking-backup',
          'version': 1,
          'backupId': 'manual-${createdAt.microsecondsSinceEpoch}',
          'createdAt': createdAt.toIso8601String(),
          'documentCount': records.length,
          'collectionCounts': counts,
          'documents': records,
        }),
      ),
    );
  }

  static BackupManifest inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const FormatException('Backup file is empty or exceeds 50 MB.');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['format'] != 'sales-tracking-backup' ||
        data['version'] != 1 ||
        data['documents'] is! Map) {
      throw const FormatException('Invalid backup file');
    }
    final createdAt = DateTime.tryParse('${data['createdAt'] ?? ''}');
    if (createdAt == null) {
      throw const FormatException('Backup date is missing or invalid.');
    }
    final documents = data['documents'] as Map;
    final counts = <String, int>{};
    for (final entry in documents.entries) {
      final path = entry.key.toString();
      final parts = path.split('/');
      if (!(parts.length == 2 ||
              (parts.length == 4 &&
                  parts.first == 'messages' &&
                  parts[2] == 'items')) ||
          !collections.contains(parts.first) ||
          parts.last.isEmpty ||
          entry.value is! Map) {
        throw FormatException('Invalid document: $path');
      }
      if (_containsSensitiveField(entry.value)) {
        throw FormatException(
          'Backup contains sensitive credential fields: $path',
        );
      }
      counts.update(parts.first, (total) => total + 1, ifAbsent: () => 1);
    }
    final declaredCount = data['documentCount'];
    if (declaredCount is! int || declaredCount != documents.length) {
      throw const FormatException('Backup document count does not match.');
    }
    return BackupManifest(
      backupId:
          '${data['backupId'] ?? 'legacy-${createdAt.microsecondsSinceEpoch}'}',
      createdAt: createdAt,
      documentCount: documents.length,
      collectionCounts: counts,
      byteLength: bytes.length,
    );
  }

  static bool _containsSensitiveField(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_isSensitiveField('${entry.key}') ||
            _containsSensitiveField(entry.value)) {
          return true;
        }
      }
    } else if (value is List) {
      return value.any(_containsSensitiveField);
    }
    return false;
  }

  static Map<String, Map<String, dynamic>> validate(Uint8List bytes) {
    inspect(bytes);
    final data = jsonDecode(utf8.decode(bytes));
    final result = <String, Map<String, dynamic>>{};
    for (final entry in (data['documents'] as Map).entries) {
      result[entry.key.toString()] = Map<String, dynamic>.from(
        decode(entry.value) as Map,
      );
    }
    return result;
  }
}
