import '../models/order.dart';
import '../utils/pricing.dart';

/// 小票上的文案（随界面语言变）。
class ReceiptLabels {
  /// 合计那一行的名字（如「合计」/「Importe adeudado」/「Total」）。
  final String labelTotal;

  /// 支付方式那一行的名字。
  final String labelPay;

  const ReceiptLabels({
    required this.labelTotal,
    required this.labelPay,
  });
}

/// 小票单头的一行「标签: 值」（如 `Fecha: 20/9/2026 5:15 p. m.`）。
///
/// 标签列会**按最长的标签对齐**（跟参考小票一样）：
/// ```
/// Fecha:    20/9/2026 5:15 a. m.
/// Pedido:   8
/// Empleado: ADMIN
/// ```
class ReceiptInfoRow {
  final String label;
  final String value;

  const ReceiptInfoRow(this.label, this.value);
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

  /// 堂食 / 外卖（例如「堂食」「外卖」）。
  final String typeLabel;

  /// 厨师单字号：1 = 正常，2 = 大（双倍高），3 = 特大（双倍宽 + 双倍高）。
  /// 见 `escpos.dart` 的 `TicketScale`：**双倍宽会让每行列数减半**，排版要跟着缩。
  final int fontSize;

  KitchenData({
    required this.table,
    required this.orderId,
    required this.createdAt,
    required this.lines,
    required this.paperWidth,
    required this.labels,
    this.isAppend = false,
    this.typeLabel = '',
    this.fontSize = 2,
  });
}

/// 小票上一行「标签 + 金额」（小计 / 折扣 / 税 这类）。
class ReceiptAmountRow {
  final String label;
  final double amount;

  /// true 时金额前面加负号（折扣就是这么显示的）。
  final bool negative;

  const ReceiptAmountRow(this.label, this.amount, {this.negative = false});
}

/// 一张小票需要的数据（不含打印机细节）。
///
/// 排版参考 `assets/receipt_print.jpg`：
/// ```
///             店名
///        地址 / 电话 / RFC（居中）
/// ----------------------------------
/// Fecha:    20/9/2026 5:15 a. m.
/// Pedido:   20260920-001  Mesa 8
/// Empleado: ADMIN
/// ----------------------------------
/// Para llevar
/// ----------------------------------
/// ARROZ CON CAMARON (MEDIANO)  $140.00
/// 1 x  $140.00
/// ...
/// ----------------------------------
/// Importe adeudado             $550.00
/// ----------------------------------
/// ```
class ReceiptData {
  final String storeName;

  /// 店名下面**居中**打的几行（地址 / 电话 / RFC …），可为空。
  final List<String> headerLines;

  /// 单头几行「标签: 值」（日期 / 单号 / 收银员 …）。
  final List<ReceiptInfoRow> infoRows;

  /// 金额符号（打在单价和金额前面，例如 `$140.00`）。
  final String currency;

  final String paymentMethodLabel;
  final List<OrderLine> lines;
  final double total;
  final String thankyou;
  final String paperWidth; // '58' | '80'
  final ReceiptLabels labels;

  /// 堂食/外卖（例如「堂食」或「外卖」），单独夹在两条横线中间。
  final String typeLine;

  /// 额外几行（例如「实收: $200.00」「找零: $50.00」），原样打印。
  final List<String> extraLines;

  /// 合计**之前**的明细行：小计 / 折扣 / 税。
  final List<ReceiptAmountRow> amountRows;

  ReceiptData({
    required this.storeName,
    required this.currency,
    required this.paymentMethodLabel,
    required this.lines,
    required this.total,
    required this.thankyou,
    required this.paperWidth,
    required this.labels,
    this.headerLines = const [],
    this.infoRows = const [],
    this.typeLine = '',
    this.extraLines = const [],
    this.amountRows = const [],
  });
}

/// 58mm≈32 列，80mm≈48 列（中文字符占 2 列）。
int receiptColumns(String paperWidth) => paperWidth == '80' ? 48 : 32;

/// 厨师单字号 → 列宽放大倍数（**双倍宽时列数减半**）。
int kitchenWidthScale(int fontSize) => fontSize >= 3 ? 2 : 1;

/// 厨师单排版真正能用的列数（已经按字号缩过）。
int kitchenColumns(String paperWidth, int fontSize) =>
    receiptColumns(paperWidth) ~/ kitchenWidthScale(fontSize);

String _two(int n) => n.toString().padLeft(2, '0');

/// 小票上的日期时间：
/// - 中文：`2026-09-20 17:15`（习惯写法）
/// - 西语 / 英语：`20/9/2026 5:15 p. m.` / `20/9/2026 5:15 PM`（跟参考小票一致）
String formatReceiptDateTime(DateTime dt, String lang) {
  if (lang == 'zh') {
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
        '${_two(dt.hour)}:${_two(dt.minute)}';
  }
  final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour < 12
      ? (lang == 'en' ? 'AM' : 'a. m.')
      : (lang == 'en' ? 'PM' : 'p. m.');
  return '${dt.day}/${dt.month}/${dt.year} $h12:${_two(dt.minute)} $ampm';
}

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

/// 把订单排成小票的一行行文本（已对齐）。
///
/// 版式照 `assets/receipt_print.jpg`：店头居中 → 单头「标签: 值」左对齐 →
/// 堂食/外卖单独一行 → 菜品「菜名(+选项) 金额」+ 下一行「数量 x 单价」→
/// 合计单独夹在两条横线中间 → 支付方式/实收/找零 → 谢谢光临居中。
List<String> buildReceiptLines(ReceiptData r) {
  final cols = receiptColumns(r.paperWidth);
  final labels = r.labels;
  final lines = <String>[];
  final divider = '-' * cols;

  // ---- 店头：店名 + 地址/电话等，全部居中 ----
  if (r.storeName.isNotEmpty) {
    lines.add(padCenter(_truncateToWidth(r.storeName, cols), cols));
  }
  for (final h in r.headerLines) {
    final t = h.trim();
    if (t.isEmpty) continue;
    lines.add(padCenter(_truncateToWidth(t, cols), cols));
  }
  lines.add(divider);

  // ---- 单头：Fecha / Pedido / Empleado …（标签列按最长的标签对齐）----
  if (r.infoRows.isNotEmpty) {
    var labelW = 0;
    for (final row in r.infoRows) {
      final w = displayWidth(row.label) + 1; // 含中文冒号
      if (w > labelW) labelW = w;
    }
    labelW += 1; // 标签和值之间空一列
    if (labelW > cols - 4) labelW = cols - 4; // 标签特别长时别把值挤没了
    for (final row in r.infoRows) {
      final label = padRight(_truncateToWidth('${row.label}:', labelW - 1), labelW);
      lines.add(label + _truncateToWidth(row.value, cols - labelW));
    }
  }

  // ---- 堂食 / 外卖：单独一行，上下都有横线 ----
  if (r.typeLine.trim().isNotEmpty) {
    lines.add(_truncateToWidth(r.typeLine.trim(), cols));
    lines.add(divider);
  }

  // ---- 菜品：菜名（+选项）一行 + 右对齐金额；下一行「数量 x 单价」----
  // 金额列：58mm 给 12 列、80mm 给 14 列（放得下 $1234.50 这种）。
  final amountW = cols >= 48 ? 14 : 12;
  final labelW = cols - amountW;

  String amountRow(String label, double amount, {bool negative = false}) {
    final text = '${negative ? '-' : ''}${r.currency}'
        '${amount.abs().toStringAsFixed(2)}';
    return padRight(_truncateToWidth(label, labelW - 1), labelW) +
        padLeft(text, amountW);
  }

  for (var i = 0; i < r.lines.length; i++) {
    final l = r.lines[i];
    // 选项跟在菜名后面（参考小票的「ARROZ CON CAMARON (MEDIANO)」）；
    // 备注（可能很长）留到下面单独一行，免得把金额挤掉。
    final opt = l.options.isEmpty ? '' : ' (${l.options.join(' / ')})';
    lines.add(padRight(_truncateToWidth('${l.name}$opt', labelW - 1), labelW) +
        padLeft('${r.currency}${l.subtotal.toStringAsFixed(2)}', amountW));
    // 第二行：`1 x  $140.00`（有单位就写 `2 份 x $28.00`）
    final unit = l.unit.trim();
    final qty = unit.isEmpty ? '${l.quantity}' : '${l.quantity} $unit';
    lines.add(_truncateToWidth(
        '$qty x  ${r.currency}${l.unitPrice.toStringAsFixed(2)}', cols));
    final note = l.note.trim();
    if (note.isNotEmpty) {
      lines.add('  ${_truncateToWidth(note, cols - 3)}');
    }
    // 每道菜之间空一行（跟参考小票一样，看起来不挤）
    if (i != r.lines.length - 1) lines.add('');
  }

  // ---- 金额区：小计 / 折扣 / 税 → 合计（合计上下都有横线）----
  lines.add(divider);
  for (final row in r.amountRows) {
    lines.add(amountRow(row.label, row.amount, negative: row.negative));
  }
  if (r.amountRows.isNotEmpty) lines.add(divider);
  lines.add(amountRow(labels.labelTotal, r.total));
  lines.add(divider);

  // ---- 支付方式 / 实收 / 找零 ----
  if (r.paymentMethodLabel.isNotEmpty && r.paymentMethodLabel != '-') {
    lines.add(_truncateToWidth(
        '${labels.labelPay}: ${r.paymentMethodLabel}', cols));
  }
  for (final extra in r.extraLines) {
    lines.add(_truncateToWidth(extra, cols));
  }
  lines.add('');
  if (r.thankyou.trim().isNotEmpty) {
    lines.add(padCenter(_truncateToWidth(r.thankyou.trim(), cols), cols));
  }

  return lines;
}

/// 把订单排成「厨房单」的一行行文本（只有菜名+数量，不含价格）。
///
/// **字号**（`KitchenData.fontSize`）会通过 [kitchenColumns] 缩小列数：
/// 特大（双倍宽）时 58mm 只剩 16 列，所以菜名会早一点被截断 —— 这是必然的
/// （字大一倍、一行就只能放一半字），想两者都要就选「大（双倍高）」。
List<String> buildKitchenLines(KitchenData k) {
  final cols = kitchenColumns(k.paperWidth, k.fontSize);
  final labels = k.labels;
  final lines = <String>[];
  final divider = '=' * cols;

  // 标题（追单时标注）
  final title = k.isAppend ? '${labels.title} ${labels.append}' : labels.title;
  lines.add(padCenter(_truncateToWidth(title, cols), cols));
  lines.add(divider);

  if (k.table.isNotEmpty) {
    lines.add(_truncateToWidth(
        '${labels.labelTable}: ${k.table}'
        '${k.typeLabel.isEmpty ? '' : '  ${k.typeLabel}'}',
        cols));
  } else if (k.typeLabel.isNotEmpty) {
    // 外卖没有桌号，就只打「外卖」
    lines.add(_truncateToWidth(k.typeLabel, cols));
  }
  lines.add(_truncateToWidth(k.orderId, cols));
  final dt = k.createdAt;
  lines.add(_truncateToWidth(
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
      '${_two(dt.hour)}:${_two(dt.minute)}',
      cols));
  lines.add(divider);

  // 菜名(左) 数量(右)；数量列也按字号缩，别把菜名挤没
  final qtyW = cols >= 32 ? 6 : 5;
  final nameW = cols - qtyW;
  lines.add(padRight(_truncateToWidth(labels.colName, nameW - 1), nameW) +
      padLeft(_truncateToWidth(labels.colQty, qtyW), qtyW));

  for (final l in k.lines) {
    lines.add(padRight(_truncateToWidth(l.name, nameW - 1), nameW) +
        padLeft(_qtyCell(l, qtyW), qtyW));
    // 选项 / 备注：缩进打在下一行（厨房必须看得见）
    final detail = l.detail;
    if (detail.isNotEmpty) {
      lines.add('  ${_truncateToWidth(detail, cols - 3)}');
    }
  }

  lines.add(divider);
  return lines;
}

/// 「数量」单元格：菜有单位（Excel 的「单位」列）时写「2 份」。
///
/// 只有**放得下**才加单位 —— 单位名太长（例如「公斤」+ 数量）就只打数字，
/// 免得把整张票的列对不齐。
String _qtyCell(OrderLine l, int width) {
  final unit = l.unit.trim();
  final plain = '${l.quantity}';
  if (unit.isEmpty) return plain;
  final withUnit = '${l.quantity} $unit';
  return displayWidth(withUnit) <= width ? withUnit : plain;
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

// ---------------------------------------------------------------------------
// 日结（每日汇总）小票
// ---------------------------------------------------------------------------

/// 日结小票上的文案。
class SummaryLabels {
  final String title; // 日结
  final String date; // 日期
  final String dineIn; // 堂食
  final String takeaway; // 外卖
  final String phoneTakeaway; // 电话外卖
  final String cash; // 现金
  final String card; // 刷卡
  final String qr; // 扫码
  final String subtotal; // 小计
  final String discount; // 折扣
  final String tax; // 税
  final String total; // 总营业额
  final String expense; // 支出
  final String net; // 净额
  final String orders; // 单数

  const SummaryLabels({
    required this.title,
    required this.date,
    required this.dineIn,
    required this.takeaway,
    required this.cash,
    required this.card,
    required this.qr,
    required this.total,
    required this.expense,
    required this.net,
    required this.orders,
    this.phoneTakeaway = 'Takeaway (Phone Call)',
    this.subtotal = 'Subtotal',
    this.discount = 'Discount',
    this.tax = 'Tax',
  });
}

/// 日结数据。
class SummaryData {
  final String storeName;
  final String dateLabel; // 例如 2026-01-01
  final String paperWidth;
  final String currency; // 店里的货币符号
  final double dineInTotal;
  final double takeawayTotal;

  /// **电话外卖**（打电话点的）的营业额 —— 0 的时候不打印这一行。
  final double phoneTakeawayTotal;

  /// 现金：币种 → 金额（MXN / USD / RMB …）。
  final Map<String, double> cashByCurrency;
  final double cardTotal;
  final double qrTotal;

  /// 小计 / 折扣 / 税（折扣与税非 0 时才多打两行）。
  final double subtotalTotal;
  final double discountTotal;
  final double taxTotal;

  final double total;
  final double expense;
  final int orderCount;
  final SummaryLabels labels;

  SummaryData({
    required this.storeName,
    required this.dateLabel,
    required this.paperWidth,
    required this.currency,
    required this.dineInTotal,
    required this.takeawayTotal,
    required this.cashByCurrency,
    required this.cardTotal,
    required this.qrTotal,
    required this.total,
    required this.expense,
    required this.orderCount,
    required this.labels,
    this.phoneTakeawayTotal = 0,
    this.subtotalTotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
  });
}

/// 排成日结小票的一行行文本。
List<String> buildSummaryLines(SummaryData d) {
  final cols = receiptColumns(d.paperWidth);
  final lines = <String>[];
  final divider = '=' * cols;
  final thin = '-' * cols;

  String row(String label, double amount, {String? symbol}) {
    final s = symbol ?? d.currency;
    return padRight(label, cols - 12) +
        padLeft('$s${amount.toStringAsFixed(2)}', 12);
  }

  if (d.storeName.isNotEmpty) lines.add(padCenter(d.storeName, cols));
  lines.add(padCenter(d.labels.title, cols));
  lines.add(divider);
  lines.add('${d.labels.date}: ${d.dateLabel}');
  lines.add(thin);

  // 左：堂食 / 外卖（电话外卖有单的时候才多打一行）
  lines.add(row(d.labels.dineIn, d.dineInTotal));
  lines.add(row(d.labels.takeaway, d.takeawayTotal));
  if (round2(d.phoneTakeawayTotal) != 0) {
    lines.add(row(d.labels.phoneTakeaway, d.phoneTakeawayTotal));
  }
  lines.add(thin);

  // 现金分币种
  if (d.cashByCurrency.isEmpty) {
    lines.add(row(d.labels.cash, 0, symbol: d.currency));
  } else {
    d.cashByCurrency.forEach((code, amount) {
      final sym = kCurrencySymbols[code] ?? d.currency;
      final label = code.isEmpty ? d.labels.cash : '${d.labels.cash} $code';
      lines.add(row(label, amount, symbol: sym));
    });
  }
  if (d.cardTotal != 0) lines.add(row(d.labels.card, d.cardTotal));
  if (d.qrTotal != 0) lines.add(row(d.labels.qr, d.qrTotal));
  lines.add(divider);

  // 小计 / 折扣 / 税：有才打（打折或收税的日子才多这几行）
  if (round2(d.discountTotal) != 0 || round2(d.taxTotal) != 0) {
    lines.add(row(d.labels.subtotal, d.subtotalTotal));
    if (round2(d.discountTotal) != 0) {
      lines.add(row(d.labels.discount, d.discountTotal));
    }
    if (round2(d.taxTotal) != 0) lines.add(row(d.labels.tax, d.taxTotal));
    lines.add(thin);
  }

  lines.add(row(d.labels.total, d.total));
  lines.add(row(d.labels.expense, d.expense));
  lines.add(row(d.labels.net, d.total - d.expense));
  lines.add(thin);
  lines.add('${d.labels.orders}: ${d.orderCount}');
  lines.add('');
  return lines;
}
