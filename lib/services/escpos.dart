import 'package:gbk_codec/gbk_codec.dart';

/// 把一行行文本编码成 ESC/POS 字节流（所有打印通道共用）。
///
/// - `0x1B 0x40`        初始化打印机
/// - `0x1B 0x61 0x00`   左对齐
/// - 每行：GBK 编码 + 换行(0x0A)   ← 中文热敏机用 GBK，不是 UTF-8
/// - `0x1D 0x56 0x42 0x00` 半切纸
List<int> buildEscPosBytes(List<String> lines) {
  final out = <int>[];
  out.addAll([0x1B, 0x40]); // 初始化
  out.addAll([0x1B, 0x61, 0x00]); // 左对齐
  for (final line in lines) {
    out.addAll(gbk.encode(line));
    out.addAll([0x0A]); // 换行
  }
  out.addAll([0x0A, 0x0A]); // 底部留白
  out.addAll([0x1D, 0x56, 0x42, 0x00]); // 半切纸
  return out;
}
