import 'dart:convert';

import 'package:archive/archive.dart';

/// 极简 xlsx 读取：只做我们需要的事 —— 把第一个工作表读成「二维字符串表」。
///
/// 为什么自己写：xlsx 本质是个 zip，里面是 XML。自己解析只有 ~150 行，
/// 且不用依赖 `excel` 包（那个包的 API 在不同大版本之间变过，容易踩坑）。
class XlsxReader {
  /// 读出第一个工作表：`rows[行][列]`，缺失的单元格是空串。
  static List<List<String>> readFirstSheet(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const XlsxException('这个文件不是有效的 xlsx（无法解压）。');
    }

    final shared = _sharedStrings(archive);
    final sheetName = _firstSheetPath(archive);
    final xml = _readText(archive, sheetName);
    if (xml == null) {
      throw const XlsxException('xlsx 里找不到工作表内容。');
    }
    return _parseSheet(xml, shared);
  }

  /// 找第一个工作表路径（默认 xl/worksheets/sheet1.xml）。
  static String _firstSheetPath(Archive archive) {
    const fallback = 'xl/worksheets/sheet1.xml';
    final candidates = archive.files
        .map((f) => f.name)
        .where((n) => n.startsWith('xl/worksheets/') && n.endsWith('.xml'))
        .toList()
      ..sort();
    if (candidates.contains(fallback)) return fallback;
    if (candidates.isNotEmpty) return candidates.first;
    return fallback;
  }

  static ArchiveFile? _file(Archive archive, String name) {
    for (final f in archive.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  static String? _readText(Archive archive, String name) {
    final f = _file(archive, name);
    if (f == null) return null;
    final data = f.content;
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return null;
  }

  /// 读 `xl/sharedStrings.xml`：所有字符串都放在这里，单元格里只存索引。
  static List<String> _sharedStrings(Archive archive) {
    final xml = _readText(archive, 'xl/sharedStrings.xml');
    if (xml == null) return const [];
    final out = <String>[];
    final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
    for (final m in siRe.allMatches(xml)) {
      final body = m.group(1) ?? '';
      final buf = StringBuffer();
      for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(body)) {
        buf.write(t.group(1) ?? '');
      }
      out.add(_unescape(buf.toString()));
    }
    return out;
  }

  static List<List<String>> _parseSheet(String xml, List<String> shared) {
    final rows = <int, Map<int, String>>{};
    var autoRow = 0;

    final rowRe = RegExp(r'<row\b([^>]*)>(.*?)</row>', dotAll: true);
    for (final rm in rowRe.allMatches(xml)) {
      final attrs = rm.group(1) ?? '';
      final body = rm.group(2) ?? '';
      final rAttr = RegExp(r'r="(\d+)"').firstMatch(attrs);
      final rowIdx = rAttr != null ? int.parse(rAttr.group(1)!) - 1 : autoRow;
      autoRow = rowIdx + 1;

      final cells = <int, String>{};
      final cellRe = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
      for (final cm in cellRe.allMatches(body)) {
        final cAttrs = cm.group(1) ?? '';
        final cBody = cm.group(2) ?? '';
        final colRef = RegExp(r'r="([A-Z]+)').firstMatch(cAttrs);
        final colIdx =
            colRef != null ? _colIndex(colRef.group(1)!) : cells.length;
        final type = RegExp(r't="([^"]+)"').firstMatch(cAttrs)?.group(1);

        String value = '';
        if (type == 'inlineStr') {
          final buf = StringBuffer();
          for (final t
              in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(cBody)) {
            buf.write(t.group(1) ?? '');
          }
          value = buf.toString();
        } else {
          final raw =
              RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(cBody)?.group(1) ??
                  '';
          if (type == 's') {
            final idx = int.tryParse(raw);
            value = (idx != null && idx >= 0 && idx < shared.length)
                ? shared[idx]
                : '';
          } else {
            value = raw;
          }
        }
        cells[colIdx] = _unescape(value).trim();
      }
      rows[rowIdx] = cells;
    }

    if (rows.isEmpty) return const [];
    final maxRow = rows.keys.reduce((a, b) => a > b ? a : b);
    final out = <List<String>>[];
    for (var i = 0; i <= maxRow; i++) {
      final cells = rows[i];
      if (cells == null || cells.isEmpty) {
        out.add(const <String>[]);
        continue;
      }
      final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
      final row = List<String>.filled(maxCol + 1, '');
      cells.forEach((c, v) {
        if (c >= 0 && c <= maxCol) row[c] = v;
      });
      out.add(row);
    }
    return out;
  }

  /// 列字母 → 0 起的下标：A→0, B→1, …, Z→25, AA→26。
  static int _colIndex(String letters) {
    var n = 0;
    for (final code in letters.codeUnits) {
      if (code < 0x41 || code > 0x5A) continue;
      n = n * 26 + (code - 0x41 + 1);
    }
    return n - 1;
  }

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        )
        .replaceAll('&amp;', '&');
  }
}

class XlsxException implements Exception {
  final String message;
  const XlsxException(this.message);
  @override
  String toString() => message;
}
