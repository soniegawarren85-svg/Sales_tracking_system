import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sales_tracking/services/qr_image_decoder.dart';
import 'package:sales_tracking/widgets/transaction_settings_dialog.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test('discount validation caps percentages at 20', () {
    expect(discountPercentValidationMessage('1'), isNull);
    expect(discountPercentValidationMessage('20'), isNull);
    expect(
      discountPercentValidationMessage('20.01'),
      'Discount must be from 1% to 20%.',
    );
    expect(
      discountPercentValidationMessage('0'),
      'Discount must be from 1% to 20%.',
    );
    expect(
      discountPercentValidationMessage('not a number'),
      'Discount must be from 1% to 20%.',
    );
  });

  test('payment method names contain letters and spaces only', () {
    expect(validPaymentMethodName('GCash'), isTrue);
    expect(validPaymentMethodName('Bank Transfer'), isTrue);
    expect(validPaymentMethodName('GCash 2'), isFalse);
    expect(validPaymentMethodName('GCash!'), isFalse);
  });

  test('QR image decoder accepts QR codes and rejects other images', () {
    final qr = Encoder.encode(
      'GCash sample QR',
      ErrorCorrectionLevel.m,
    ).matrix!;
    const scale = 5;
    const quietZone = 4;
    final width = (qr.width + quietZone * 2) * scale;
    final image = img.Image(width: width, height: width, numChannels: 4);
    for (var y = 0; y < width; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
    for (var y = 0; y < qr.height; y++) {
      for (var x = 0; x < qr.width; x++) {
        if (qr.get(x, y) == 1) {
          for (var dy = 0; dy < scale; dy++) {
            for (var dx = 0; dx < scale; dx++) {
              image.setPixelRgba(
                (x + quietZone) * scale + dx,
                (y + quietZone) * scale + dy,
                0,
                0,
                0,
                255,
              );
            }
          }
        }
      }
    }

    expect(
      decodeQrImage(Uint8List.fromList(img.encodePng(image))),
      'GCash sample QR',
    );

    final blank = img.Image(width: 64, height: 64, numChannels: 4);
    expect(
      () => decodeQrImage(Uint8List.fromList(img.encodePng(blank))),
      throwsFormatException,
    );
  });
}
