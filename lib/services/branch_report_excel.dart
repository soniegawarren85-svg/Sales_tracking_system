import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'branch_report_csv.dart';
import 'branch_report_data.dart';

const _spreadsheetNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relationshipNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _chartNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';

Uint8List branchReportExcel(
  BranchReportData data,
  DateTime start,
  DateTime end, {
  String? branchId,
  DateTime? now,
}) {
  final rows = branchReportRows(data, start, end, branchId: branchId, now: now);
  final archive = Archive();
  void addPart(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final columnCount = rows.fold<int>(
    1,
    (maxColumns, row) => math.max(maxColumns, row.length),
  );
  final rowCount = rows.length;
  final sheetReferences = <_AnalyticsChart>[];

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.isNotEmpty && row.first == '3. SALES ANALYTICS') {
      final headerRow = rowIndex + 1;
      if (headerRow >= rows.length) continue;
      final analyticsHeaders = rows[headerRow].map((cell) => '$cell').toList();
      final salesColumn = analyticsHeaders.indexOf('Sales');
      final netSalesColumn = analyticsHeaders.indexOf('Net sales');
      final firstDataRow = headerRow + 1;
      var lastDataRow = firstDataRow;
      while (lastDataRow < rows.length &&
          rows[lastDataRow].isNotEmpty &&
          rows[lastDataRow].first != 'TOTAL' &&
          !'${rows[lastDataRow].first}'.startsWith('4. ')) {
        lastDataRow++;
      }
      final categoryColumn = analyticsHeaders.indexOf('Date / hour');
      if (categoryColumn >= 0 &&
          salesColumn >= 0 &&
          netSalesColumn >= 0 &&
          lastDataRow > firstDataRow) {
        sheetReferences.add(
          _AnalyticsChart(
            sectionRow: rowIndex,
            firstDataRow: firstDataRow,
            lastDataRow: lastDataRow - 1,
            categoryColumn: categoryColumn,
            salesColumn: salesColumn,
            netSalesColumn: netSalesColumn,
          ),
        );
      }
    }
  }

  final chartRelationshipId = sheetReferences.isEmpty ? '' : 'rId1';
  addPart('[Content_Types].xml', _contentTypes(sheetReferences.length));
  addPart(
    '_rels/.rels',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
  );
  addPart(
    'xl/workbook.xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="$_spreadsheetNamespace" xmlns:r="$_relationshipNamespace"><sheets><sheet name="Branch Report" sheetId="1" r:id="rId1"/></sheets></workbook>''',
  );
  addPart(
    'xl/_rels/workbook.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
  );
  addPart('xl/styles.xml', _stylesXml);
  addPart(
    'xl/worksheets/sheet1.xml',
    _sheetXml(rows, columnCount, rowCount, chartRelationshipId),
  );
  if (sheetReferences.isNotEmpty) {
    addPart(
      'xl/worksheets/_rels/sheet1.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>''',
    );
    addPart('xl/drawings/drawing1.xml', _drawingXml(sheetReferences));
    addPart(
      'xl/drawings/_rels/drawing1.xml.rels',
      _drawingRelationships(sheetReferences.length),
    );
    for (var index = 0; index < sheetReferences.length; index++) {
      addPart(
        'xl/charts/chart${index + 1}.xml',
        _chartXml(sheetReferences[index], index),
      );
    }
  }

  final bytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(bytes);
}

bool _isHeaderRow(List<dynamic> row) =>
    row.isNotEmpty &&
    (row.first == 'ID' ||
        row.first == 'Metric' ||
        row.first == 'Date / hour' ||
        row.first == 'Rank' ||
        row.first == 'Receipt');

String _sheetXml(
  List<List<dynamic>> rows,
  int columnCount,
  int rowCount,
  String chartRelationshipId,
) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="$_spreadsheetNamespace" xmlns:r="$_relationshipNamespace">'
    '<dimension ref="A1:${_columnName(columnCount - 1)}$rowCount"/>'
    '<sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
    '<cols>',
  );
  for (var column = 0; column < columnCount; column++) {
    final width = switch (column) {
      0 => 16,
      1 => 20,
      2 => 30,
      _ => 17,
    };
    buffer.write(
      '<col min="${column + 1}" max="${column + 1}" width="$width" customWidth="1"/>',
    );
  }
  buffer.write('</cols><sheetData>');

  var currentHeaders = const <String>[];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (_isHeaderRow(row)) currentHeaders = row.map((cell) => '$cell').toList();
    final rowStyle = _rowStyle(row, rowIndex);
    final height = rowIndex == 0
        ? ' ht="30" customHeight="1"'
        : rowStyle == 3
        ? ' ht="34" customHeight="1"'
        : rowStyle == 2
        ? ' ht="24" customHeight="1"'
        : '';
    buffer.write('<row r="${rowIndex + 1}"$height>');
    for (var column = 0; column < row.length; column++) {
      final value = row[column];
      final reference = '${_columnName(column)}${rowIndex + 1}';
      final header = column < currentHeaders.length
          ? currentHeaders[column]
          : '';
      final styled = _cellStyle(rowStyle, header, value, column);
      _writeCell(buffer, reference, value, header, styled);
    }
    buffer.write('</row>');
  }
  buffer.write('</sheetData>');
  if (chartRelationshipId.isNotEmpty) {
    buffer.write('<drawing r:id="$chartRelationshipId"/>');
  }
  buffer.write('</worksheet>');
  return buffer.toString();
}

int _rowStyle(List<dynamic> row, int rowIndex) {
  if (rowIndex == 0) return 1;
  if (row.isEmpty) return 0;
  final first = '${row.first}';
  if (first == 'BRANCH' || RegExp(r'^\d+\. ').hasMatch(first)) return 2;
  if (_isHeaderRow(row)) return 3;
  if (first == 'TOTAL') return 4;
  if (first == 'Categories' ||
      first == 'Bundle' ||
      first == 'Beverages' ||
      first == 'Add-ons') {
    return 2;
  }
  return 0;
}

int _cellStyle(int rowStyle, String header, dynamic value, int column) {
  if (rowStyle == 1 || rowStyle == 2 || rowStyle == 3) return rowStyle;
  if (rowStyle == 4 && header == 'Total cost') return 5;
  if (rowStyle == 4) return 4;
  if (_isDateHeader(header) &&
      value is String &&
      DateTime.tryParse(value) != null) {
    return header == 'Date / hour' || header == 'Date / time' ? 7 : 6;
  }
  if (_isMoneyHeader(header)) return 8;
  if (value is num || _isCountHeader(header)) return 9;
  if (column == 0 && value is String && value == 'Total cost') return 2;
  return 0;
}

void _writeCell(
  StringBuffer buffer,
  String reference,
  dynamic value,
  String header,
  int style,
) {
  if (value == null || value == '') return;
  if (value is num) {
    buffer.write('<c r="$reference" s="$style"><v>${value.toString()}</v></c>');
    return;
  }
  final text = '$value';
  if (_isDateHeader(header)) {
    final date = DateTime.tryParse(text);
    if (date != null) {
      final excelDate = _excelDate(date);
      buffer.write(
        '<c r="$reference" s="$style"><v>${excelDate.toStringAsFixed(8)}</v></c>',
      );
      return;
    }
  }
  if (_isMoneyHeader(header) || _isCountHeader(header)) {
    final number = num.tryParse(text);
    if (number != null && number.isFinite) {
      buffer.write(
        '<c r="$reference" s="$style"><v>${number.toString()}</v></c>',
      );
      return;
    }
  }
  buffer.write(
    '<c r="$reference" s="$style" t="inlineStr"><is><t xml:space="preserve">${_xmlEscape(text)}</t></is></c>',
  );
}

bool _isDateHeader(String header) =>
    header == 'Allocation date' ||
    header == 'Expiry' ||
    header == 'Date / hour' ||
    header == 'Date / time' ||
    header == 'Generated';

bool _isMoneyHeader(String header) {
  final lower = header.toLowerCase();
  return lower.contains('price') ||
      lower.contains('sales') ||
      lower.contains('profit') ||
      lower.contains('cost') ||
      lower.contains('revenue') ||
      lower.contains('vat') ||
      lower.contains('tax') ||
      lower.contains('discount') ||
      lower.contains('refund') ||
      lower.contains('loss') ||
      lower == 'amount / count' ||
      lower == 'total';
}

bool _isCountHeader(String header) {
  final lower = header.toLowerCase();
  return lower.contains('allocation') ||
      lower.contains('sold items') ||
      lower.contains('transactions') ||
      lower == 'quantity' ||
      lower == 'rank' ||
      lower == 'starting' ||
      lower == 'remaining' ||
      lower == 'allocated in period';
}

double _excelDate(DateTime date) {
  final utc = DateTime.utc(
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second,
  );
  return utc.difference(DateTime.utc(1899, 12, 30)).inSeconds / 86400;
}

String _columnName(int index) {
  var value = index + 1;
  final result = StringBuffer();
  while (value > 0) {
    final remainder = (value - 1) % 26;
    result.writeCharCode(65 + remainder);
    value = (value - 1) ~/ 26;
  }
  return result.toString().split('').reversed.join();
}

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _contentTypes(int charts) {
  final drawingOverride = charts == 0
      ? ''
      : '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>';
  final chartOverrides = List.generate(
    charts,
    (index) =>
        '<Override PartName="/xl/charts/chart${index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>',
  ).join();
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>$drawingOverride$chartOverrides</Types>''';
}

String _drawingXml(List<_AnalyticsChart> charts) {
  final anchors = <String>[];
  for (var index = 0; index < charts.length; index++) {
    final chart = charts[index];
    anchors.add(
      '''<xdr:twoCellAnchor><xdr:from><xdr:col>12</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${chart.sectionRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>22</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${chart.sectionRow + 20}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="${index + 2}" name="Sales Analytics Chart ${index + 1}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="$_chartNamespace"><c:chart xmlns:c="$_chartNamespace" xmlns:r="$_relationshipNamespace" r:id="rId${index + 1}"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>''',
    );
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="$_chartNamespace">$anchors</xdr:wsDr>''';
}

String _drawingRelationships(int charts) {
  final relationships = List.generate(
    charts,
    (index) =>
        '<Relationship Id="rId${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart${index + 1}.xml"/>',
  ).join();
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$relationships</Relationships>''';
}

String _chartXml(_AnalyticsChart chart, int chartIndex) {
  final categoryRange = _range(
    chart.categoryColumn,
    chart.firstDataRow,
    chart.lastDataRow,
  );
  String seriesXml(int index, String name, int column, String color) {
    final valueRange = _range(column, chart.firstDataRow, chart.lastDataRow);
    return '''<c:ser><c:idx val="$index"/><c:order val="$index"/><c:tx><c:v>$name</c:v></c:tx><c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr><c:cat><c:numRef><c:f>$categoryRange</c:f><c:numFmt formatCode="dd/mm/yyyy hh:mm" sourceLinked="0"/></c:numRef></c:cat><c:val><c:numRef><c:f>$valueRange</c:f></c:numRef></c:val></c:ser>''';
  }

  const categoryAxisId = 48650112;
  final valueAxisId = categoryAxisId + chartIndex + 1;
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace xmlns:c="$_chartNamespace" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:date1904 val="0"/><c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:rPr lang="en-US"/><a:t>Sales Analytics</a:t></a:r><a:endParaRPr lang="en-US"/></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:plotArea><c:layout/><c:barChart><c:barDir val="bar"/><c:grouping val="clustered"/><c:varyColors val="0"/>${seriesXml(0, 'Sales', chart.salesColumn, 'D46A94')}${seriesXml(1, 'Net sales', chart.netSalesColumn, '7A1845')}<c:gapWidth val="70"/><c:overlap val="0"/><c:axId val="$categoryAxisId"/><c:axId val="$valueAxisId"/></c:barChart><c:catAx><c:axId val="$categoryAxisId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:axPos val="l"/><c:tickLblPos val="nextTo"/><c:crossAx val="$valueAxisId"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/></c:catAx><c:valAx><c:axId val="$valueAxisId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:axPos val="b"/><c:majorGridlines/><c:numFmt formatCode="#,##0.00" sourceLinked="0"/><c:tickLblPos val="nextTo"/><c:crossAx val="$categoryAxisId"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx></c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart><c:printSettings><c:headerFooter/><c:pageMargins l="0.25" r="0.25" t="0.5" b="0.5" header="0.2" footer="0.2"/></c:printSettings></c:chartSpace>''';
}

String _range(int column, int firstRow, int lastRow) =>
    "'Branch Report'!\$${_columnName(column)}\$${firstRow + 1}:\$${_columnName(column)}\$${lastRow + 1}";

class _AnalyticsChart {
  const _AnalyticsChart({
    required this.sectionRow,
    required this.firstDataRow,
    required this.lastDataRow,
    required this.categoryColumn,
    required this.salesColumn,
    required this.netSalesColumn,
  });

  final int sectionRow;
  final int firstDataRow;
  final int lastDataRow;
  final int categoryColumn;
  final int salesColumn;
  final int netSalesColumn;
}

const _stylesXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="$_spreadsheetNamespace"><numFmts count="3"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/><numFmt numFmtId="166" formatCode="#,##0.00"/></numFmts><fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="18"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF6F244F"/><name val="Calibri"/></font></fonts><fills count="7"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF6F244F"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD46A94"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFCE4EC"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFE8A3"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8F3E8"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFE7BDD0"/></left><right style="thin"><color rgb="FFE7BDD0"/></right><top style="thin"><color rgb="FFE7BDD0"/></top><bottom style="thin"><color rgb="FFE7BDD0"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="10"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0"/><xf numFmtId="0" fontId="3" fillId="6" borderId="1" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0"/><xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0"/><xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0"/><xf numFmtId="3" fontId="0" fillId="0" borderId="1" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';
