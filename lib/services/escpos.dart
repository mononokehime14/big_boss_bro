import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';

/// 小票里的一行。
///
/// - 普通行：给 [text]，按默认/指定 [codec] 编码。
/// - 原始行：给 [raw]（已经是最终字节），用于需要精确控制指令的场景（如中文能力探测）。
class TicketLine {
  final String text;
  final String? codec;
  final List<int>? raw;

  const TicketLine(this.text, {this.codec, this.raw});
}

/// 支持的小票编码（内码）。
const List<String> kReceiptCodecs = ['gbk', 'utf8', 'latin1', 'cp850'];

/// 生成一条「强制 GBK 中文模式」的原始字节行（方式 A：`FS &` 进出中文模式）。
///
/// 与当前设置的编码无关，所以能给出确定结论。
List<int> gbkProbeFs(String text) => <int>[
      0x1C, 0x26, // FS & 进入中文模式
      ...gbkBytes(text),
      0x0A, // 换行
      0x1C, 0x2E, // FS . 退出中文模式
    ];

/// 中文探测（方式 B：先 `ESC t 255` 选代码页再发 GBK）。
///
/// 少数打印机的中文模式是靠 `ESC t` 选页而不是 `FS &`。
List<int> gbkProbeEscT(String text) => <int>[
      0x1B, 0x74, 0xFF, // ESC t 255
      0x1C, 0x26, // FS &
      ...gbkBytes(text),
      0x0A,
      0x1C, 0x2E, // FS .
      0x1B, 0x74, 0x00, // ESC t 0 复位
    ];

/// 把文本编成**真正的 GBK 字节流**。
///
/// ⚠️ 踩过的坑（曾导致所有中文乱码）：`gbk_codec` 里有**两个** codec：
/// - `gbk.encode(text)` → 返回的是 **16 位 GBK 码点**（如 `中` = 0xD6D0 = 54992），**不是字节**！
///   直接当字节发出去会被截断成 1 个错字节 → 中文全乱（ASCII 因为码点 <256 一直正常）。
/// - `gbk_bytes.encode(text)` → 这才是把码点拆成两个字节的正确字节流（`中` → `0xD6 0xD0`）。
///
/// 已验证的真值（来自该包的数据表）：中=D6D0、恭=B9A7、，=A3AC、！=A3A1；ASCII 不在表里、原样单字节。
List<int> gbkBytes(String text) {
  final raw = gbk_bytes.encode(text);
  // 兜底：万一有字符不在表里、码点 > 255 被直接塞进来，替换成 '?'，避免被截断成乱码字节。
  return raw.map((b) => (b >= 0 && b <= 0xFF) ? b : 0x3F).toList();
}

/// 双倍宽高的一行 —— 用来验证 **ESC/POS 指令到底有没有生效**。
///
/// 如果这行打出来**明显比别的字大**，说明指令原样送达了打印机（RAW 通道正常）；
/// 如果大小和普通字一样，说明中间那层（通常是 Windows 驱动）**没有把指令原样透传**，
/// 那中文/西语乱码就是它造成的。
List<int> doubleSizeBytes(String text) => <int>[
      0x1B, 0x21, 0x30, // ESC ! 0x30 = 双倍宽 + 双倍高
      ...ascii.encode(text),
      0x0A,
      0x1B, 0x21, 0x00, // 复位
    ];

/// 把一行行文本编码成 ESC/POS 字节流（所有打印通道共用）。
///
/// 指令说明：
/// - `1B 40`        初始化打印机
/// - `1B 4D 00`     选 **Font A**（12×24）。80mm 可打 576 点，Font A 每字 12 点 → 48 列正好铺满；
///                  若用 Font B（9×17），48 列只有 432 点 ≈ 60mm，纸宽就“没铺满”。
/// - `1C 26`        `FS &` 进入**中文模式**（仅当编码为 gbk）。中文热敏机不加这一条会乱码。
/// - `1B 61 00`     左对齐
/// - 每行：按编码转字节 + 换行（带 [TicketLine.raw] 的行直接用原始字节）
/// - `1D 56 42 00`  半切纸
List<int> buildEscPosBytes(
  List<TicketLine> lines, {
  String codec = 'gbk',
  bool fontA = true,
}) {
  final out = <int>[];
  out.addAll([0x1B, 0x40]); // 初始化
  if (fontA) out.addAll([0x1B, 0x4D, 0x00]); // ESC M 0 → Font A
  if (codec == 'gbk') out.addAll([0x1C, 0x26]); // FS & → 中文模式（GBK）
  out.addAll([0x1B, 0x61, 0x00]); // 左对齐

  for (final line in lines) {
    final raw = line.raw;
    if (raw != null) {
      out.addAll(raw);
    } else {
      out.addAll(encodeText(line.text, line.codec ?? codec));
      out.addAll([0x0A]); // 换行
    }
  }

  out.addAll([0x0A, 0x0A]); // 底部留白
  out.addAll([0x1D, 0x56, 0x42, 0x00]); // 半切纸
  return out;
}

/// 把一段文本按指定编码转成字节。
List<int> encodeText(String text, String codec) {
  switch (codec) {
    case 'utf8':
      return utf8.encode(text);
    case 'latin1':
      return _latin1(text);
    case 'cp850':
      return _cp850(text);
    case 'gbk':
    default:
      // 注意：必须用 gbk_bytes（字节流），不能用 gbk（那是 16 位码点）。
      return gbkBytes(text);
  }
}

/// ISO-8859-1：码点 <= 0xFF 的直接做字节，其余用 '?'。
List<int> _latin1(String s) =>
    s.runes.map((r) => r <= 0xFF ? r : 0x3F).toList();

/// CP850（也兼容 CP437 对西语字符的编码）：只覆盖常用西语/符号字符，其余用 '?'。
List<int> _cp850(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else {
      final b = _cp850Map[r];
      out.add(b ?? 0x3F); // 不认识的字符 → '?'
    }
  }
  return out;
}

/// 常用字符 → CP850 字节（西语重音、常用符号；CP437 对这些字符基本一致）。
const Map<int, int> _cp850Map = {
  0x00A1: 0xAD, // ¡
  0x00A2: 0xBD, // ¢
  0x00A3: 0x9C, // £
  0x00A5: 0xBE, // ¥
  0x00A7: 0xEE, // §
  0x00A9: 0xB8, // ©
  0x00AA: 0xA6, // ª
  0x00AB: 0xAE, // «
  0x00AC: 0xAA, // ¬
  0x00AD: 0xF0, // 软连字符（少见）
  0x00B0: 0xF1, // °
  0x00B1: 0xEA, // ±
  0x00B2: 0xF6, // ²
  0x00B3: 0xF5, // ³
  0x00B4: 0xE8, // ´
  0x00B5: 0xDF, // µ
  0x00B6: 0xED, // ¶
  0x00B7: 0xF3, // ·
  0x00B8: 0xF0, // ¸
  0x00B9: 0xF4, // ¹
  0x00BA: 0xA7, // º
  0x00BB: 0xAF, // »
  0x00BC: 0xAC, // ¼
  0x00BD: 0xAB, // ½
  0x00BE: 0xEC, // ¾
  0x00BF: 0xA8, // ¿
  0x00C0: 0xB7, // À
  0x00C1: 0xB5, // Á
  0x00C2: 0xB6, // Â
  0x00C3: 0xC7, // Ã
  0x00C4: 0x8E, // Ä
  0x00C5: 0x8F, // Å
  0x00C6: 0x92, // Æ
  0x00C7: 0x80, // Ç
  0x00C8: 0xD4, // È
  0x00C9: 0x90, // É
  0x00CA: 0xD2, // Ê
  0x00CB: 0xD3, // Ë
  0x00CC: 0xD8, // Ì
  0x00CD: 0xD5, // Í
  0x00CE: 0xD6, // Î
  0x00CF: 0xD7, // Ï
  0x00D0: 0xD1, // Ð
  0x00D1: 0xA5, // Ñ
  0x00D2: 0xDC, // Ò
  0x00D3: 0xD9, // Ó
  0x00D4: 0xDB, // Ô
  0x00D5: 0xDE, // Õ
  0x00D6: 0x99, // Ö
  0x00D7: 0x9E, // ×
  0x00D8: 0x9D, // Ø
  0x00D9: 0xE4, // Ù
  0x00DA: 0xE2, // Ú
  0x00DB: 0xE3, // Û
  0x00DC: 0x9A, // Ü
  0x00DD: 0xE6, // Ý
  0x00DE: 0xE1, // Þ
  0x00DF: 0xDA, // ß
  0x00E0: 0x85, // à
  0x00E1: 0xA0, // á
  0x00E2: 0x83, // â
  0x00E3: 0xC6, // ã
  0x00E4: 0x84, // ä
  0x00E5: 0x86, // å
  0x00E6: 0x91, // æ
  0x00E7: 0x87, // ç
  0x00E8: 0x8A, // è
  0x00E9: 0x82, // é
  0x00EA: 0x88, // ê
  0x00EB: 0x89, // ë
  0x00EC: 0x8D, // ì
  0x00ED: 0xA1, // í
  0x00EE: 0x8C, // î
  0x00EF: 0x8B, // ï
  0x00F0: 0xD0, // ð
  0x00F1: 0xA4, // ñ
  0x00F2: 0x95, // ò
  0x00F3: 0xA2, // ó
  0x00F4: 0x93, // ô
  0x00F5: 0xDD, // õ
  0x00F6: 0x94, // ö
  0x00F7: 0xEF, // ÷
  0x00F8: 0x9B, // ø
  0x00F9: 0x97, // ù
  0x00FA: 0xA3, // ú
  0x00FB: 0x96, // û
  0x00FC: 0x81, // ü
  0x00FD: 0xE5, // ý
  0x00FE: 0xE0, // þ
  0x00FF: 0x98, // ÿ
};
