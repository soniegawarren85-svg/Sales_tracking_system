import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class BackupManifest {
  const BackupManifest({
    required this.backupId,
    required this.backupName,
    required this.applicationVersion,
    required this.createdAt,
    required this.documentCount,
    required this.collectionCounts,
    required this.byteLength,
  });

  final String backupId;
  final String backupName;
  final String applicationVersion;
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
    'backup_audit_logs',
    'backup_history',
    'allocation_checklist',
    'branches',
    'budget_history',
    'coffee_flavors',
    'coffee_addons',
    'coffee_products',
    'completed_sales',
    'counters',
    'daily_reports',
    'events',
    'inventory_bundle_actions',
    'inventory_reconciliations',
    'inventory_reports',
    'messages',
    'message_status',
    'notifications',
    'pending_order_history',
    'pending_orders',
    'sales_inventory',
    'staff_budget',
    'staff_cash_drawer',
    'staff_inventory',
    'staff_inventory_history',
    'staff_login_sessions',
    'staff_profiles',
    'staff_requests',
    'stock_adjustments',
    'system_counters',
    'super_admin_profiles',
    'daily_stock_reports',
    'low_stock_reports',
    'return_batches',
    'return_batch_items',
    'cash_float_requests',
    'cash_float_history',
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

  static dynamic decode(dynamic value, {FirebaseFirestore? firestore}) {
    final db = firestore ?? FirebaseFirestore.instance;
    if (value is List) {
      return value.map((item) => decode(item, firestore: db)).toList();
    }
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
          return db.doc(value['path'] as String);
        case 'blob':
          return Blob(base64Decode(value['data'] as String));
      }
      return value.map(
        (k, v) => MapEntry(k.toString(), decode(v, firestore: db)),
      );
    }
    return value;
  }

  static Future<Uint8List> export({
    FirebaseFirestore? firestore,
    String backupName = 'Manual backup',
    String? backupId,
    void Function(int completed, int total, String collection)? onProgress,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final records = <String, dynamic>{};
    for (var index = 0; index < collections.length; index++) {
      final name = collections[index];
      onProgress?.call(index, collections.length, name);
      try {
        final snapshot = await db
            .collection(name)
            .get(const GetOptions(source: Source.server));
        for (final doc in snapshot.docs) {
          if (name == 'backup_history' &&
              doc.data()['status'] == 'in_progress') {
            continue;
          }
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
    onProgress?.call(
      collections.length,
      collections.length,
      'Validating export',
    );
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
          'backupId': backupId ?? 'manual-${createdAt.microsecondsSinceEpoch}',
          'backupName': backupName.trim().isEmpty
              ? 'Manual backup'
              : backupName.trim(),
          'applicationVersion': '1.0.7',
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
    final declaredCounts = data['collectionCounts'];
    if (declaredCounts is! Map ||
        declaredCounts.length != counts.length ||
        counts.entries.any(
          (entry) => declaredCounts[entry.key] != entry.value,
        )) {
      throw const FormatException('Backup collection counts do not match.');
    }
    final appVersion = '${data['applicationVersion'] ?? ''}';
    final appMajor = int.tryParse(appVersion.split('.').first);
    if (appMajor != null && appMajor != 1) {
      throw FormatException(
        'Backup app version $appVersion is not compatible with this restore format.',
      );
    }
    return BackupManifest(
      backupId:
          '${data['backupId'] ?? 'legacy-${createdAt.microsecondsSinceEpoch}'}',
      backupName: '${data['backupName'] ?? 'Imported backup'}',
      applicationVersion: '${data['applicationVersion'] ?? 'legacy'}',
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

  static Map<String, Map<String, dynamic>> validate(
    Uint8List bytes, {
    FirebaseFirestore? firestore,
  }) {
    inspect(bytes);
    final data = jsonDecode(utf8.decode(bytes));
    final result = <String, Map<String, dynamic>>{};
    for (final entry in (data['documents'] as Map).entries) {
      result[entry.key.toString()] = Map<String, dynamic>.from(
        decode(entry.value, firestore: firestore) as Map,
      );
    }
    return result;
  }

  /// Merges validated records by their original document paths in safe batches.
  /// Existing fields absent from the backup and documents absent from the
  /// backup are left untouched.
  static Future<int> restoreMerge(
    Map<String, Map<String, dynamic>> documents, {
    required FirebaseFirestore firestore,
    void Function(int completed, int total)? onProgress,
  }) async {
    final entries = documents.entries.toList();
    var completed = 0;
    for (var start = 0; start < entries.length; start += 400) {
      final batch = firestore.batch();
      final page = entries.skip(start).take(400);
      for (final entry in page) {
        batch.set(
          firestore.doc(entry.key),
          entry.value,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      completed += page.length;
      onProgress?.call(completed, entries.length);
    }
    return completed;
  }
}
