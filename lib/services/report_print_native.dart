import 'activity_log.dart';
import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> printReportDocument({
  required String name,
  required Future<Uint8List> Function() build,
}) async {
  final bytes = await build();
  if (bytes.isEmpty) throw StateError('The report is empty.');
  final printed = await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
  if (printed) await ActivityLog.record('report_printed', 'Printed report $name');
}
