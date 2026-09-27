import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.ThemeData> reportPdfTheme() async => pw.ThemeData.withFont(
  base: pw.Font.ttf(await rootBundle.load('Assets/fonts/roboto-regular.ttf')),
  bold: pw.Font.ttf(await rootBundle.load('Assets/fonts/roboto-bold.ttf')),
);
