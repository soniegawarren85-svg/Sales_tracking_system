import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThermalPrinterDevice {
  final String name;
  final String address;

  const ThermalPrinterDevice({required this.name, required this.address});

  factory ThermalPrinterDevice.fromMap(Map<String, dynamic> map) =>
      ThermalPrinterDevice(
        name: map['name']?.toString() ?? '',
        address: map['address']?.toString() ?? '',
      );
}

class ThermalPrinterStatus {
  final String? name;
  final String? address;
  final bool isConnected;
  final bool isConnecting;
  final int paperWidth;

  const ThermalPrinterStatus({
    this.name,
    this.address,
    this.isConnected = false,
    this.isConnecting = false,
    this.paperWidth = 58,
  });

  String get label => isConnecting
      ? 'Connecting'
      : isConnected
      ? 'Connected'
      : 'Disconnected';
}

class ThermalPrinterService {
  ThermalPrinterService._();

  static final ThermalPrinterService instance = ThermalPrinterService._();
  static const _addressKey = 'thermalPrinterAddress';
  static const _nameKey = 'thermalPrinterName';
  static const _paperWidthKey = 'thermalPrinterPaperWidth';
  static const _timeout = Duration(seconds: 45);
  static const _channel = MethodChannel(
    'com.example.sales_tracking/thermal_printer',
  );

  final ValueNotifier<ThermalPrinterStatus> status =
      ValueNotifier<ThermalPrinterStatus>(const ThermalPrinterStatus());
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_addressKey);
    final name = prefs.getString(_nameKey);
    final paperWidth = prefs.getInt(_paperWidthKey) == 80 ? 80 : 58;
    status.value = ThermalPrinterStatus(
      address: address,
      name: name,
      paperWidth: paperWidth,
    );

    if (address == null || address.isEmpty || !_isAndroid) return;
    try {
      if (!await Permission.bluetoothConnect.isGranted ||
          !await Permission.bluetoothScan.isGranted) {
        return;
      }
      if (!await _bluetoothEnabled) return;
      await _connect(address, name ?? 'Saved printer');
    } catch (error) {
      debugPrint('Automatic thermal printer reconnect failed: $error');
      status.value = ThermalPrinterStatus(
        address: address,
        name: name,
        paperWidth: paperWidth,
      );
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> get _bluetoothEnabled => _channel
      .invokeMethod<bool>('bluetoothEnabled')
      .then((enabled) => enabled ?? false);

  Future<void> _requireAndroid() async {
    await initialize();
    if (!_isAndroid) {
      throw UnsupportedError(
        'Bluetooth thermal printing is currently available on Android only.',
      );
    }
  }

  Future<void> _requestBluetoothPermission() async {
    final scanPermission = await Permission.bluetoothScan.request();
    if (!scanPermission.isGranted) {
      if (scanPermission.isPermanentlyDenied || scanPermission.isRestricted) {
        throw StateError(
          'Bluetooth scan permission is blocked. Enable Nearby devices permission in Android Settings.',
        );
      }
      throw StateError(
        'Bluetooth scan permission was denied. Allow Nearby devices access to connect to the printer.',
      );
    }

    final connectPermission = await Permission.bluetoothConnect.request();
    if (connectPermission.isGranted) return;
    if (connectPermission.isPermanentlyDenied ||
        connectPermission.isRestricted) {
      throw StateError(
        'Bluetooth connect permission is blocked. Enable Nearby devices permission in Android Settings.',
      );
    }
    throw StateError(
      'Bluetooth connect permission was denied. Allow Nearby devices access to connect to the printer.',
    );
  }

  Future<List<ThermalPrinterDevice>> scanPairedPrinters() async {
    await _requireAndroid();
    await _requestBluetoothPermission();
    if (!await _bluetoothEnabled) {
      throw StateError(
        'Bluetooth is turned off. Enable Bluetooth and scan again.',
      );
    }
    final devices = await _channel.invokeListMethod<dynamic>('pairedPrinters');
    return (devices ?? const [])
        .map(
          (item) => ThermalPrinterDevice.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((printer) => printer.address.isNotEmpty)
        .toList();
  }

  Future<void> connect(ThermalPrinterDevice printer) async {
    await _requireAndroid();
    await _requestBluetoothPermission();
    if (!await _bluetoothEnabled) {
      throw StateError(
        'Bluetooth is turned off. Enable Bluetooth and try again.',
      );
    }
    await _connect(printer.address, printer.name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressKey, printer.address);
    await prefs.setString(_nameKey, printer.name);
  }

  Future<void> _connect(String address, String name) async {
    status.value = ThermalPrinterStatus(
      address: address,
      name: name,
      paperWidth: status.value.paperWidth,
      isConnecting: true,
    );
    try {
      if (await _connectionStatus) {
        await _channel.invokeMethod<bool>('disconnect');
      }
      final connected = await _channel
          .invokeMethod<bool>('connect', {'address': address})
          .timeout(_timeout);
      if (connected != true) {
        throw StateError('Android did not confirm the printer connection.');
      }
      status.value = ThermalPrinterStatus(
        address: address,
        name: name,
        paperWidth: status.value.paperWidth,
        isConnected: true,
      );
    } catch (_) {
      status.value = ThermalPrinterStatus(
        address: address,
        name: name,
        paperWidth: status.value.paperWidth,
      );
      rethrow;
    }
  }

  Future<void> reconnect() async {
    await _requireAndroid();
    final current = status.value;
    final address = current.address;
    if (address == null || address.isEmpty) {
      throw StateError('Scan and select a printer first.');
    }
    await _requestBluetoothPermission();
    if (!await _bluetoothEnabled) {
      throw StateError(
        'Bluetooth is turned off. Enable Bluetooth and try again.',
      );
    }
    await _connect(address, current.name ?? 'Saved printer');
  }

  Future<void> disconnect() async {
    await _requireAndroid();
    await _requestBluetoothPermission();
    final current = status.value;
    final disconnected = await _channel.invokeMethod<bool>('disconnect');
    if (disconnected != true && current.isConnected) {
      throw StateError('Unable to disconnect from the printer.');
    }
    status.value = ThermalPrinterStatus(
      address: current.address,
      name: current.name,
      paperWidth: current.paperWidth,
    );
  }

  Future<void> setPaperWidth(int width) async {
    if (width != 58 && width != 80) {
      throw ArgumentError.value(width, 'width', 'Use 58 or 80 mm.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_paperWidthKey, width);
    final current = status.value;
    status.value = ThermalPrinterStatus(
      address: current.address,
      name: current.name,
      isConnected: current.isConnected,
      isConnecting: current.isConnecting,
      paperWidth: width,
    );
  }

  Future<void> printReceipt(Map<String, dynamic> receipt) async {
    await _requireAndroid();
    if (!status.value.isConnected || !await _connectionStatus) {
      await reconnect();
    }
    final bytes = await _buildReceipt(receipt, status.value.paperWidth);
    final sent = await _channel
        .invokeMethod<bool>('writeBytes', {'bytes': bytes})
        .timeout(_timeout);
    if (sent != true) {
      status.value = ThermalPrinterStatus(
        address: status.value.address,
        name: status.value.name,
        paperWidth: status.value.paperWidth,
      );
      throw StateError('Printer did not accept the receipt data.');
    }
  }

  Future<bool> get _connectionStatus => _channel
      .invokeMethod<bool>('connectionStatus')
      .then((connected) => connected ?? false);

  Future<void> printTestReceipt() => printReceipt({
    'salesId': 'TEST-PRINT',
    'branchName': 'Printer Test',
    'staffName': 'Cashier',
    'timestamp': DateTime.now(),
    'items': [
      {'name': 'Thermal printer test', 'quantity': 1, 'price': 1},
    ],
    'subtotal': 1,
    'discount': 0,
    'total': 1,
    'paymentMode': 'Cash',
    'paidAmount': 1,
    'change': 0,
  });

  Future<List<int>> _buildReceipt(
    Map<String, dynamic> receipt,
    int paperWidth,
  ) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );
    final bytes = <int>[];
    final items = (receipt['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final timestamp = _toDate(receipt['timestamp']) ?? DateTime.now();
    final subtotal = _number(receipt['subtotal']);
    final discount = _number(receipt['discount']);
    final total = _number(receipt['total']);
    final paymentMethod = receipt['paymentMode']?.toString() ?? 'Cash';

    bytes.addAll(generator.reset());
    bytes.addAll(
      generator.text(
        'SALES TRACKING SYSTEM',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
        linesAfter: 1,
      ),
    );
    bytes.addAll(
      generator.text(
        _ascii(receipt['branchName']?.toString() ?? 'Branch'),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.text(
        'Receipt: ${_ascii(receipt['salesId']?.toString() ?? 'N/A')}',
      ),
    );
    bytes.addAll(generator.text('Date: ${_formatDate(timestamp)}'));
    bytes.addAll(
      generator.text(
        'Cashier: ${_ascii(receipt['staffName']?.toString() ?? 'Staff')}',
      ),
    );
    bytes.addAll(generator.hr());

    for (final item in items) {
      final itemName = item['name']?.toString() ?? 'Item';
      final variant = item['variant']?.toString().trim() ?? '';
      final coffeeSize = item['coffeeSize']?.toString().trim() ?? '';
      final detail = variant.isNotEmpty ? variant : coffeeSize;
      final name = _ascii(detail.isEmpty ? itemName : '$itemName ($detail)');
      final quantity = _number(item['quantity']).toInt();
      final price = _number(item['price']);
      bytes.addAll(generator.text(name));
      bytes.addAll(
        generator.row([
          PosColumn(
            text: '$quantity x PHP ${price.toStringAsFixed(2)}',
            width: 7,
          ),
          PosColumn(
            text: 'PHP ${(quantity * price).toStringAsFixed(2)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    bytes.addAll(generator.hr());
    bytes.addAll(_receiptRow(generator, 'Subtotal', subtotal));
    if (discount > 0) {
      final discountType = _ascii(
        receipt['discountType']?.toString() ?? 'Discount',
      );
      bytes.addAll(_receiptRow(generator, discountType, -discount));
    }
    bytes.addAll(_receiptRow(generator, 'TOTAL', total, bold: true));
    bytes.addAll(generator.text('Payment: ${_ascii(paymentMethod)}'));
    if (paymentMethod.toLowerCase() == 'cash') {
      bytes.addAll(
        _receiptRow(generator, 'Received', _number(receipt['paidAmount'])),
      );
      bytes.addAll(
        _receiptRow(generator, 'Change', _number(receipt['change'])),
      );
    } else {
      final reference = receipt['gcashTransactionId']?.toString().trim() ?? '';
      if (reference.isNotEmpty) {
        bytes.addAll(generator.text('Reference: ${_ascii(reference)}'));
      }
    }
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.text(
        'Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 2,
      ),
    );
    bytes.addAll(generator.cut());
    return bytes;
  }

  List<int> _receiptRow(
    Generator generator,
    String label,
    double amount, {
    bool bold = false,
  }) => generator.row([
    PosColumn(
      text: _ascii(label),
      width: 7,
      styles: PosStyles(bold: bold),
    ),
    PosColumn(
      text: 'PHP ${amount.toStringAsFixed(2)}',
      width: 5,
      styles: PosStyles(align: PosAlign.right, bold: bold),
    ),
  ]);

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _ascii(String value) => value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
}
