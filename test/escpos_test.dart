import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';

import 'package:big_boss_bro/services/escpos.dart';

/// 判断 [haystack] 里是否包含连续子序列 [needle]（用来检查 ESC/POS 指令字节）。
bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('编码（GBK / latin1）', () {
    // ⚠️ 这条测试曾经抓到过一个真 bug：
    //    gbk_codec 的 `gbk.encode()` 返回的是 16 位 GBK 码点（中 = 0xD6D0 = 54992），
    //    不是字节流；当字节发出去会被截断成 1 个错字节 → 中文乱码（ASCII 却正常）。
    //    正确用法是 `gbk_bytes.encode()`（会把码点拆成两个字节）。
    test('GBK 字节与标准值一致：中 = D6 D0，A = 41', () {
      expect(encodeText('中', 'gbk'), [0xD6, 0xD0]);
      expect(encodeText('A', 'gbk'), [0x41]);
    });

    test('中文按 2 字节/字编码，且能原样解回', () {
      const s = '恭喜您，打印成功！'; // 9 个字符（含全角标点）
      final bytes = encodeText(s, 'gbk');
      expect(bytes.length, 18, reason: '9 个字符 × 2 字节');
      expect(gbk_bytes.decode(bytes), s, reason: 'GBK 编解码必须能往返');
    });

    test('每个字节都在 0..255（否则发出会被截断 → 乱码）', () {
      final bytes = encodeText('恭喜您，打印成功！下单', 'gbk');
      for (final b in bytes) {
        expect(b, inInclusiveRange(0, 255));
      }
    });

    test('ASCII 在 GBK 下保持单字节（所以数字/日期一直正常）', () {
      expect(encodeText('Gracias', 'gbk'),
          [0x47, 0x72, 0x61, 0x63, 0x69, 0x61, 0x73]);
    });

    test('latin1 对西语重音给出单字节', () {
      expect(encodeText('áéíóúñ', 'latin1'),
          [0xE1, 0xE9, 0xED, 0xF3, 0xFA, 0xF1]);
    });
  });

  group('指令字节（回答“初始化/中文模式指令有没有加”）', () {
    test('编码=gbk 时，字节流里有 初始化 / FontA / 中文模式(FS &) / 切纸', () {
      final b =
          buildEscPosBytes([const TicketLine('AB')], codec: 'gbk', fontA: true);
      expect(_contains(b, [0x1B, 0x40]), isTrue, reason: 'ESC @ 初始化');
      expect(_contains(b, [0x1B, 0x4D, 0x00]), isTrue, reason: 'ESC M 0 → Font A');
      expect(_contains(b, [0x1C, 0x26]), isTrue, reason: 'FS & → 中文模式');
      expect(_contains(b, [0x1D, 0x56, 0x42, 0x00]), isTrue,
          reason: 'GS V B 0 → 切纸');
    });

    test('编码=latin1 时不发中文模式指令', () {
      final b = buildEscPosBytes([const TicketLine('AB')], codec: 'latin1');
      expect(_contains(b, [0x1C, 0x26]), isFalse);
    });

    test('双倍大小指令存在（[BIG] 那行用它验证指令是否生效）', () {
      final b = doubleSizeBytes('X');
      expect(_contains(b, [0x1B, 0x21, 0x30]), isTrue);
    });

    test('中文探测行 = FS & + 正确 GBK 字节（中 = D6 D0）', () {
      final b = gbkProbeFs('中');
      expect(_contains(b, [0x1C, 0x26]), isTrue, reason: 'FS &');
      expect(_contains(b, [0xD6, 0xD0]), isTrue, reason: 'GBK 中');
      expect(_contains(b, [0x1C, 0x2E]), isTrue, reason: 'FS . 退出');
    });
  });
}
