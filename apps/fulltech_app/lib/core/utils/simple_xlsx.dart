import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class SimpleXlsxSheet {
  const SimpleXlsxSheet({required this.name, required this.rows});

  final String name;
  final List<List<Object?>> rows;
}

Uint8List buildSimpleXlsx(List<SimpleXlsxSheet> sheets) {
  final archive = Archive();

  void add(String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  }

  final safeSheets = sheets.isEmpty
      ? const [SimpleXlsxSheet(name: 'Hoja1', rows: [])]
      : sheets;

  add('[Content_Types].xml', _contentTypes(safeSheets.length));
  add('_rels/.rels', _rootRels());
  add('xl/workbook.xml', _workbook(safeSheets));
  add('xl/_rels/workbook.xml.rels', _workbookRels(safeSheets.length));
  add('xl/styles.xml', _styles());
  for (var i = 0; i < safeSheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _worksheet(safeSheets[i].rows));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, List<List<String>>> readSimpleXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final workbookXml = _archiveText(archive, 'xl/workbook.xml');
  final relsXml = _archiveText(archive, 'xl/_rels/workbook.xml.rels');
  final sheetNames = <String, String>{};
  final relTargets = <String, String>{};

  for (final match in RegExp(
    r'<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"',
  ).allMatches(workbookXml)) {
    sheetNames[_unescapeXml(match.group(2)!)] = _unescapeXml(match.group(1)!);
  }
  for (final match in RegExp(
    r'<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"',
  ).allMatches(relsXml)) {
    relTargets[_unescapeXml(match.group(1)!)] = _unescapeXml(match.group(2)!);
  }

  final result = <String, List<List<String>>>{};
  for (final entry in sheetNames.entries) {
    final target = relTargets[entry.key];
    if (target == null || !target.contains('worksheets/')) continue;
    final path = target.startsWith('xl/') ? target : 'xl/$target';
    final xml = _archiveText(archive, path);
    result[entry.value] = _readWorksheet(xml);
  }
  return result;
}

String _archiveText(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null) return '';
  final content = file.content;
  return utf8.decode(content, allowMalformed: true);
}

String _contentTypes(int sheetCount) {
  final sheetOverrides = [
    for (var i = 1; i <= sheetCount; i++)
      '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '$sheetOverrides'
      '</Types>';
}

String _rootRels() {
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
}

String _workbook(List<SimpleXlsxSheet> sheets) {
  final sheetXml = [
    for (var i = 0; i < sheets.length; i++)
      '<sheet name="${_escapeXml(_safeSheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>$sheetXml</sheets>'
      '</workbook>';
}

String _workbookRels(int sheetCount) {
  final sheetRels = [
    for (var i = 1; i <= sheetCount; i++)
      '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$sheetRels'
      '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
}

String _styles() {
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F6F8B"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" applyFont="1" applyFill="1"/></cellXfs>'
      '</styleSheet>';
}

String _worksheet(List<List<Object?>> rows) {
  final maxColumns = rows.fold<int>(
    0,
    (max, row) => row.length > max ? row.length : max,
  );
  final widths = [
    for (var col = 1; col <= maxColumns; col++)
      '<col min="$col" max="$col" width="${col <= 2 ? 24 : 16}" customWidth="1"/>',
  ].join();
  final rowXml = [
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
      _rowXml(rowIndex + 1, rows[rowIndex], header: rowIndex == 0),
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<cols>$widths</cols><sheetData>$rowXml</sheetData>'
      '</worksheet>';
}

String _rowXml(int rowNumber, List<Object?> values, {required bool header}) {
  final cells = [
    for (var i = 0; i < values.length; i++)
      _cellXml(_cellRef(i + 1, rowNumber), values[i], header: header),
  ].join();
  return '<row r="$rowNumber">$cells</row>';
}

String _cellXml(String ref, Object? value, {required bool header}) {
  final style = header ? ' s="1"' : '';
  if (value is num) {
    return '<c r="$ref"$style><v>${value.toString()}</v></c>';
  }
  final text = _escapeXml((value ?? '').toString());
  return '<c r="$ref" t="inlineStr"$style><is><t>$text</t></is></c>';
}

List<List<String>> _readWorksheet(String xml) {
  final rows = <List<String>>[];
  for (final rowMatch in RegExp(
    r'<row[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final cellsByColumn = <int, String>{};
    var lastColumn = 0;
    for (final cellMatch in RegExp(
      r'<c([^>]*)>(.*?)</c>',
      dotAll: true,
    ).allMatches(rowMatch.group(1)!)) {
      final attrs = cellMatch.group(1)!;
      final body = cellMatch.group(2)!;
      final refMatch = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs);
      final column = refMatch == null
          ? lastColumn + 1
          : _columnIndex(refMatch.group(1)!);
      lastColumn = column;
      final textMatch = RegExp(
        r'<t[^>]*>(.*?)</t>',
        dotAll: true,
      ).firstMatch(body);
      final valueMatch = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body);
      cellsByColumn[column] = _unescapeXml(
        textMatch?.group(1) ?? valueMatch?.group(1) ?? '',
      );
    }
    if (cellsByColumn.isEmpty) continue;
    final width = cellsByColumn.keys.reduce((a, b) => a > b ? a : b);
    rows.add([for (var i = 1; i <= width; i++) cellsByColumn[i] ?? '']);
  }
  return rows;
}

String _cellRef(int column, int row) => '${_columnName(column)}$row';

String _columnName(int column) {
  var value = column;
  final chars = <String>[];
  while (value > 0) {
    value -= 1;
    chars.insert(0, String.fromCharCode(65 + (value % 26)));
    value ~/= 26;
  }
  return chars.join();
}

int _columnIndex(String name) {
  var value = 0;
  for (final code in name.codeUnits) {
    value = value * 26 + (code - 64);
  }
  return value;
}

String _safeSheetName(String name) {
  final clean = name.replaceAll(RegExp(r'[\[\]\:\*\?\/\\]'), ' ').trim();
  if (clean.isEmpty) return 'Hoja';
  return clean.length > 31 ? clean.substring(0, 31) : clean;
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _unescapeXml(String value) {
  return value
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
