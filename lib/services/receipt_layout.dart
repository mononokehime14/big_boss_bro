import '../models/order.dart';

/// 小票上的文案（随界面语言变）。
class ReceiptLabels {
  final String colName;
  final String colQty;
  final String colUnit;
  final String colAmt;
  final String labelTotal;
  final String labelPay;

  const ReceiptLabels({
    required this.colName,
    required this.colQty,
    required this.colUnit,
    required this.colAmt,
    required this.labelTotal,
    required this.labelPay,
  });
}

/// 厨房单上的文案。
class KitchenLabels {
  final String title; // 厨房单
  final String labelTable; // 桌号
  final String colName; // 菜名
  final String colQty; // 数量
  final String append; // (追加)

  const KitchenLabels({
    required this.title,
    required this.labelTable,
    required this.colName,
    required this.colQty,
    required this.append,
  });
}

/// 一张厨房单需要的数据。
class KitchenData {
  final String table;
  final String orderId;
  final DateTime createdAt;
  final List<OrderLine> lines;
  final String paperWidth;
  final KitchenLabels labels;
  final bool isAppend;

  KitchenData({
    required this.table,
    required this.orderId,
    required this.createdAt,
    required this.lines,
    required this.paperWidth,
    required this.labels,
    this.isAppend = false,
  });
}

/// 一张小票需要的数据（不含打印机细节）。
class ReceiptData {
  final String storeName;
  final String currency;
  final String orderId;
  final DateTime createdAt;
  final String paymentMethodLabel;
  final List<OrderLine> lines;
  final double total;
  final String thankyou;
  final String paperWidth; // '58' | '80'
  final ReceiptLabels labels;

  ReceiptData({
    required this.storeName,
    required this.currency,
    required this.orderId,
    required this.createdAt,
    required this.paymentMethodLabel,
    required this.lines,
    required this.total,
    required this.thankyou,
    required this.paperWidth,
    required this.labels,
  });
}

/// 58mm≈32 列，80mm≈48 列（中文字符占 2 列）。
int receiptColumns(String paperWidth) => paperWidth == '80' ? 48 : 32;

/// 显示宽度：宽字符（中文/全角）算 2 列，其余 1 列。
int displayWidth(String s) {
  int w = 0;
  for (final rune in s.runes) {
    w += _isWide(rune) ? 2 : 1;
  }
  return w;
}

bool _isWide(int rune) {
  // 简化判断：常见中文/全角符号落在这些区间。
  return (rune >= 0x2E80 && rune <= 0xA4CF) ||
      (rune >= 0xAC00 && rune <= 0xD7A3) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6) ||
      (rune >= 0x3000 && rune <= 0x303F);
}

String padRight(String s, int width) {
  final d = width - displayWidth(s);
  return d > 0 ? s + (' ' * d) : s;
}

String padLeft(String s, int width) {
  final d = width - displayWidth(s);
  return d > 0 ? (' ' * d) + s : s;
}

String padCenter(String s, int width) {
  final d = width - displayWidth(s);
  if (d <= 0) return s;
  final left = d ~/ 2;
  final right = d - left;
  return (' ' * left) + s + (' ' * right);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 把订单排成小票的一行行文本（已对齐）。
List<String> buildReceiptLines(ReceiptData r) {
  final cols = receiptColumns(r.paperWidth);
  final labels = r.labels;
  final lines = <String>[];
  final divider = '-' * cols;

  if (r.storeName.isNotEmpty) {
    lines.add(padCenter(r.storeName, cols));
  }
  lines.add(padLeft(r.orderId, cols));
  final dt = r.createdAt;
  lines.add(padLeft(
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
      '${_two(dt.hour)}:${_two(dt.minute)}', cols));
  lines.add(divider);

  // 表头：菜名(左) 数量(中) 单价(右) 金额(右)
  final nameW = 14;
  final qtyW = 4;
  final unitW = 6;
  final amtW = cols - nameW - qtyW - unitW;
  lines.add(padRight(labels.colName, nameW) +
      padLeft(labels.colQty, qtyW) +
      padLeft(labels.colUnit, unitW) +
      padLeft(labels.colAmt, amtW));
  lines.add(divider);

  for (final l in r.lines) {
    // 按显示列宽截断菜名（中文占 2 列），避免长菜名撑爆排版
    lines.add(padRight(_truncateToWidth(l.name, nameW - 1), nameW) +
        padRight('${l.quantity}', qtyW) +
        padLeft(l.unitPrice.toStringAsFixed(2), unitW) +
        padLeft(l.subtotal.toStringAsFixed(2), amtW));
    // 选项 / 备注：缩进打在下一行
    final detail = l.detail;
    if (detail.isNotEmpty) {
      lines.add('  ${_truncateToWidth(detail, cols - 3)}');
    }
  }

  lines.add(divider);
  lines.add(padRight(labels.labelTotal, cols - unitW) +
      padLeft('${r.currency}${r.total.toStringAsFixed(2)}', unitW));
  lines.add(padRight(labels.labelPay, cols - 12) +
      padLeft(r.paymentMethodLabel, 12));
  lines.add('');
  lines.add(padCenter(r.thankyou, cols));

  return lines;
}

/// 把订单排成「厨房单」的一行行文本（只有菜名+数量，不含价格）。
List<String> buildKitchenLines(KitchenData k) {
  final cols = receiptColumns(k.paperWidth);
  final labels = k.labels;
  final lines = <String>[];
  final divider = '=' * cols;

  // 标题（追单时标注）
  final title = k.isAppend ? '${labels.title} ${labels.append}' : labels.title;
  lines.add(padCenter(title, cols));
  lines.add(divider);

  if (k.table.isNotEmpty) {
    lines.add('${labels.labelTable}: ${k.table}');
  }
  lines.add(k.orderId);
  final dt = k.createdAt;
  lines.add(
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}');
  lines.add(divider);

  // 菜名(左) 数量(右)
  final nameW = cols - 6;
  const qtyW = 6;
  lines.add(padRight(labels.colName, nameW) + padLeft(labels.colQty, qtyW));

  for (final l in k.lines) {
    lines.add(padRight(_truncateToWidth(l.name, nameW - 1), nameW) +
        padLeft('${l.quantity}', qtyW));
    // 选项 / 备注：缩进打在下一行（厨房必须看得见）
    final detail = l.detail;
    if (detail.isNotEmpty) {
      lines.add('  ${_truncateToWidth(detail, cols - 3)}');
    }
  }

  lines.add(divider);
  return lines;
}

/// 按**显示列宽**截断字符串（中文算 2 列），避免长菜名撑爆排版。
String _truncateToWidth(String s, int width) {
  int w = 0;
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final cw = _isWide(rune) ? 2 : 1;
    if (w + cw > width) break;
    w += cw;
    buf.writeCharCode(rune);
  }
  return buf.toString();
}
