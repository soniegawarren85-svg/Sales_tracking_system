import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String decodeQrImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('The selected file is not a supported image.');
  }
  final pixels = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final binarizer in <Binarizer Function()>[
    () => HybridBinarizer(source),
    () => GlobalHistogramBinarizer(source),
  ]) {
    try {
      return QRCodeReader()
          .decode(BinaryBitmap(binarizer()), hints: hints)
          .text;
    } on ReaderException {
      // Some clear QR images decode with local thresholding, while others
      // need the global histogram strategy. Try both before reporting failure.
    }
  }
  throw const FormatException(
    'QR code not readable. Upload a clear, complete QR image and try again.',
  );
}
