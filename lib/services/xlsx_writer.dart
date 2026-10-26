import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 极简 xlsx **写出**：把二维字符串表写成一个能被 Excel / WPS 打开、
/// 也能被 [XlsxReader] / `MenuImporter` 重新读回来的 `.xlsx`。
///
/// 为什么自己写：项目里已经有 `XlsxReader`（xlsx = zip + XML），
/// 再引一个 excel 包会多一套依赖/API 变化；这里只需要"写第一个工作表"。
///
/// 单元格一律用 **inlineStr**（不搞 sharedStrings），中文 / 西语 / emoji
/// 原样 UTF-8 写进去；Excel 可能提示"数字以文本形式存储"，不影响导入。
class XlsxWriter {
  const XlsxWriter._();

  /// [rows] 的第一行通常放表头；空字符串的格子会被跳过。
  ///
  /// [sheetName] 是 Excel 底部看到的工作表名（不要放 `/ \ ? * [ ]` 等字符）。
  static Uint8List fromRows(
    List<List<String>> rows, {
    String sheetName = 'Menu',
  }) {
    var maxCols = 0;
    for (final row in rows) {
      if (row.length > maxCols) maxCols = row.length;
    }
    final lastCol = maxCols == 0 ? 'A' : _colName(maxCols - 1);
    final lastRow = rows.isEmpty ? 1 : rows.length;

    final sheet = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main">')
      // dimension / sheetViews 不是必须的，但加上 Excel / openpyxl 都更省心
      ..write('<dimension ref="A1:$lastCol$lastRow"/>')
      ..write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>')
      // 列宽：让「菜名 / 选项」看起来正常一点，不影响导入
      ..write('<cols>')
      ..write('<col min="1" max="2" width="18" customWidth="1"/>')
      ..write('<col min="3" max="3" width="14" customWidth="1"/>')
      ..write('<col min="4" max="5" width="12" customWidth="1"/>')
      ..write('<col min="6" max="7" width="10" customWidth="1"/>')
      ..write('<col min="8" max="99" width="22" customWidth="1"/>')
      ..write('</cols>')
      ..write('<sheetData>');

    for (var r = 0; r < rows.length; r++) {
      sheet.write('<row r="${r + 1}">');
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final value = row[c];
        if (value.isEmpty) continue;
        final ref = '${_colName(c)}${r + 1}';
        sheet
          ..write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">')
          ..write(_escapeXml(value))
          ..write('</t></is></c>');
      }
      sheet.write('</row>');
    }
    sheet
      ..write('</sheetData>')
      ..write('</worksheet>');

    final files = <String, String>{
      '[Content_Types].xml': _contentTypes,
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook(sheetName),
      'xl/_rels/workbook.xml.rels': _workbookRels,
      'xl/worksheets/sheet1.xml': sheet.toString(),
      'xl/styles.xml': _styles,
    };

    final archive = Archive();
    for (final e in files.entries) {
      final bytes = Uint8List.fromList(utf8.encode(e.value));
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('xlsx 压缩失败');
    }
    return Uint8List.fromList(encoded);
  }

  /// 0 → A，25 → Z，26 → AA。
  static String _colName(int index) {
    var n = index + 1;
    var out = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      out = String.fromCharCode(65 + m) + out;
      n = (n - 1) ~/ 26;
    }
    return out;
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _workbook(String sheetName) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${_escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';

  static const String _workbookRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '</Relationships>';

  static const String _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" '
      'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
      '<borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
