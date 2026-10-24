import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/thermal_printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.sales_tracking/thermal_printer');
  final printer = ThermalPrinterService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await printer.initialize();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    printer.status.value = const ThermalPrinterStatus();
  });

  test(
    'printed receipt shows inclusive VAT, tendered amount, and shop name',
    () async {
      final calls = <String>[];
      String printed = '';
      printer.status.value = const ThermalPrinterStatus(
        name: 'AngelZ Thermal Printer',
        address: 'saved-printer',
        isConnected: true,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'writeBytes') {
              printed = latin1.decode(List<int>.from(call.arguments['bytes']));
            }
            return true;
          });
      await printer.printReceipt({
        'salesId': 'S-123',
        'staffName': 'Ana Cruz',
        'staffPublicId': 'ST-004',
        'branchName': 'SM Dagupan',
        'branchAddress': '123 Main Street, Dagupan City',
        'taxTin': '123-456-789-000',
        'items': [
          {'name': 'Cookie', 'quantity': 1, 'price': 99},
        ],
        'subtotal': 99,
        'total': 99,
        'tax': 10.61,
        'taxRate': .12,
        'paidAmount': 99,
        'change': 0,
        'paymentMode': 'Cash',
      });
      expect(calls, ['connectionStatus', 'writeBytes']);
      expect(printed, contains("Angel'z Bites Cupcakes"));
      expect(printed, contains('Cashier: Ana Cruz'));
      expect(printed, contains('Staff ID: ST-004'));
      expect(printed, contains('SM Dagupan'));
      expect(printed, contains('123 Main Street, Dagupan City'));
      expect(printed, contains('BIR TIN: 123-456-789-000'));
      expect(printed, contains('Printer: AngelZ Thermal Printer'));
      expect(
        printed.indexOf('Printer: AngelZ Thermal Printer'),
        lessThan(printed.indexOf('Thank you for your purchase!')),
      );
      expect(printed, contains('Cash tendered'));
      expect(printed, contains('10.61'));
      expect(printed, contains('PHP 99.00'));
      expect(printed, isNot(contains('Net of sales')));
      expect(printed, isNot(contains('Net of tax')));
    },
  );

  for (final classification in ['nonVat', 'vat']) {
    test(
      'printed $classification receipt shows tax and discount breakdown',
      () async {
        String printed = '';
        printer.status.value = const ThermalPrinterStatus(
          address: 'saved-printer',
          isConnected: true,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'writeBytes') {
                printed = latin1.decode(
                  List<int>.from(call.arguments['bytes']),
                );
              }
              return true;
            });
        await printer.printReceipt({
          'salesId': 'S-discounted',
          'items': [
            {'name': 'Cookie', 'quantity': 1, 'price': 99},
          ],
          'subtotal': 99,
          'discount': 9.9,
          'discountType': 'Senior',
          'total': 89.1,
          'taxClassification': classification,
          'tax': classification == 'vat' ? 9.55 : 0,
          'taxRate': classification == 'vat' ? .12 : 0,
          'paidAmount': 89.1,
          'change': 0,
          'paymentMode': 'Cash',
        });
        expect(printed, contains('Subtotal'));
        expect(printed, contains('Senior'));
        expect(printed, contains('-9.90'));
        expect(printed, contains('PHP 89.10'));
        if (classification == 'vat') {
          expect(printed, contains('VAT (12% incl.)'));
          expect(printed, contains('PHP 9.55'));
          expect(printed, isNot(contains('Non VAT')));
        } else {
          expect(printed, contains('Non VAT'));
          expect(printed, isNot(contains('VAT (12%')));
          expect(printed, contains('PHP 0.00'));
        }
      },
    );
  }

  test('missing saved printer fails without discovery or a write', () async {
    final calls = <String>[];
    printer.status.value = const ThermalPrinterStatus();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return false;
        });
    await expectLater(
      printer.printReceipt({'salesId': 'saved-sale'}),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });
}
