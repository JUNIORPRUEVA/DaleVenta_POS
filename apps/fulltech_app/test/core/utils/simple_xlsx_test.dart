import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/utils/simple_xlsx.dart';

void main() {
  test('readSimpleXlsx reads shared string cells from Excel workbooks', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8"?>'
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="Catalogo" sheetId="1" r:id="rId1"/></sheets>'
              '</workbook>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '<?xml version="1.0" encoding="UTF-8"?>'
              '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">'
              '<si><t>producto</t></si>'
              '<si><t>precio</t></si>'
              '<si><t>Mouse optico</t></si>'
              '<si><t>350</t></si>'
              '</sst>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          '<?xml version="1.0" encoding="UTF-8"?>'
              '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
              '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>'
              '</sheetData>'
              '</worksheet>',
        ),
      );

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(readSimpleXlsx(bytes), {
      'Catalogo': [
        ['producto', 'precio'],
        ['Mouse optico', '350'],
      ],
    });
  });
}
