import '../models/order.dart';
import '../utils/pricing.dart';
import 'escpos.dart';

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

  /// 「等待」（电话外卖的等待时间那一行）。
  final String wait;

  /// 「分钟」。
  final String minutes;

  const KitchenLabels({
    required this.title,
    required this.labelTable,
    required this.colName,
    required this.colQty,
    required this.append,
    this.wait = '',
    this.minutes = '',
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

  /// 是不是**外卖 / 电话外卖**（= `Order.isTakeaway`）。
  ///
  /// true 时顶部会多打一行**特大字**：外卖单的**名字**（没名字就打系统给的号 [dailyNo]）——
  /// 堂食靠桌号认单，外卖只能靠名字 / 号，厨房才不会拿错。
  final bool isTakeaway;

  /// **外卖单的名字**（堂食恒为空）。见 `models/order.dart` 的 `Order.label`。
  final String orderLabel;

  /// **当天第几号外卖**（系统给的号，1 起；0 = 老数据没号）。
  ///
  /// 外卖单**没起名字**时，顶上那行大字打的就是它（`#3`）—— 见 `buildKitchenRows` ③段。
  final int dailyNo;

  /// **要等多久（分钟）**：电话外卖填了才有值（0 = 不打这一行）。
  /// 见 `models/order.dart` 的 `Order.waitMinutes`。
  final int waitMinutes;

  /// 这是第几张（1 起）。厨房单通常打两张，票面要能一眼分清。
  final int copyIndex;

  /// 一共打几张（1 = 不打编号）。
  final int copyTotal;

  KitchenData({
    required this.table,
    required this.orderId,
    required this.createdAt,
    required this.lines,
    required this.paperWidth,
    required this.labels,
    this.isAppend = false,
    this.typeLabel = '',
    this.isTakeaway = false,
    this.orderLabel = '',
    this.dailyNo = 0,
    this.waitMinutes = 0,
    this.copyIndex = 1,
    this.copyTotal = 1,
  });
}

/// 小票 / 厨房单里的**一行**：文本 + 这一行自己的字号（可选加粗）。
///
/// 为什么一行一行带字号：一张票上要混几种大小才好看 ——
/// 「厨师单 1」用「大」、地点/外卖/名字/等待时间/菜品用「特大」、
/// 顾客小票的**合计**也是加大加粗（见 `buildReceiptRows`）。
class TicketRow {
  final String text;
  final TicketScale scale;

  /// 这一行要不要加粗：厨房单的**菜品行**看 `escpos.dart` 的 `kKitchenBoldItemNames`；
  /// 小票的**合计行**恒定加粗。
  final bool bold;

  const TicketRow(this.text, [this.scale = TicketScale.normal]) : bold = false;

  /// 加粗版（菜品行、小票合计用它）。
  const TicketRow.bold(this.text, [this.scale = TicketScale.normal])
      : bold = true;
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

/// **菜品行的字号：固定「特大」**（双倍宽 + 双倍高）。
///
/// 不做成设置项（厨师要隔着两米看清菜名，没有"想调小"的理由）。
/// 代价是**列数减半**：58mm 只剩 16 列、80mm 24 列 → 长菜名会**折到下一行**
/// （见 [buildKitchenRows]），所以排版必须用 [kitchenItemColumns] 换算。
const TicketScale kKitchenItemScale = TicketScale.xlarge;

/// **菜品行**能用的列数（特大 = 双倍宽 → 纸张列数减半）：58mm = 16 列、80mm = 24 列。
///
/// ⚠️ 只适用于**菜品行**。虚线 / 表头 / 选项 / 备注这些**普通字号**的行要用
/// [receiptColumns]（纸张原始列数），别拿这个去截它们 —— 那会白白浪费半张纸。
int kitchenItemColumns(String paperWidth) => receiptColumns(paperWidth) ~/ 2;

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

/// 把订单排成小票的**一行行**（每行带自己的字号 / 字重）。
///
/// 版式照 `assets/receipt_print.jpg`：店头居中 → 单头「标签: 值」左对齐 →
/// 堂食/外卖单独一行 → 菜品「菜名(+选项) 金额」+ 下一行「数量 x 单价」→
/// **合计（加大加粗）**单独夹在两条横线中间 → 支付方式/实收/找零 → 谢谢光临居中。
///
/// 合计那一行是票面上唯一放大的行：
/// **特大**（双倍宽 + 双倍高）+ **加粗**；特大放不下（西语的「Importe adeudado」+ 金额
/// 就超过 16 列）自动退回**大**（只加高，列数不变）—— 所以永远不会被切。
List<TicketRow> buildReceiptRows(ReceiptData r) {
  final cols = receiptColumns(r.paperWidth);
  final labels = r.labels;
  final rows = <TicketRow>[];
  final divider = '-' * cols;

  // ---- 店头：店名 + 地址/电话等，全部居中 ----
  if (r.storeName.isNotEmpty) {
    rows.add(TicketRow(padCenter(_truncateToWidth(r.storeName, cols), cols)));
  }
  for (final h in r.headerLines) {
    final t = h.trim();
    if (t.isEmpty) continue;
    rows.add(TicketRow(padCenter(_truncateToWidth(t, cols), cols)));
  }
  rows.add(TicketRow(divider));

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
      rows.add(TicketRow(label + _truncateToWidth(row.value, cols - labelW)));
    }
  }

  // ---- 堂食 / 外卖：单独一行，上下都有横线 ----
  if (r.typeLine.trim().isNotEmpty) {
    rows.add(TicketRow(_truncateToWidth(r.typeLine.trim(), cols)));
    rows.add(TicketRow(divider));
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
    rows.add(TicketRow(
        padRight(_truncateToWidth('${l.name}$opt', labelW - 1), labelW) +
            padLeft('${r.currency}${l.subtotal.toStringAsFixed(2)}', amountW)));
    // 第二行：`1 x  $140.00`（有单位就写 `2 份 x $28.00`）
    final unit = l.unit.trim();
    final qty = unit.isEmpty ? '${l.quantity}' : '${l.quantity} $unit';
    rows.add(TicketRow(_truncateToWidth(
        '$qty x  ${r.currency}${l.unitPrice.toStringAsFixed(2)}', cols)));
    final note = l.note.trim();
    if (note.isNotEmpty) {
      // 备注**折行**打，不截断 —— 这是要紧的话（"不要香菜"），一个字都不能少
      for (final s in _wrapToWidth(note, cols - 3)) {
        rows.add(TicketRow('  $s'));
      }
    }
    // 每道菜之间空一行（跟参考小票一样，看起来不挤）
    if (i != r.lines.length - 1) rows.add(TicketRow(''));
  }

  // ---- 金额区：小计 / 折扣 / 税 → 合计（合计上下都有横线）----
  rows.add(TicketRow(divider));
  for (final row in r.amountRows) {
    rows.add(TicketRow(amountRow(row.label, row.amount, negative: row.negative)));
  }
  if (r.amountRows.isNotEmpty) rows.add(TicketRow(divider));

  // ---- 合计：**加大加粗**（下面还单独留一条横线，票面上一眼就看到）----
  final totalText = '${r.currency}${r.total.toStringAsFixed(2)}';
  final totalAmountW = displayWidth(totalText);
  // 特大要放得下「标签 + 至少一格 + 金额」，放不下就退回「大」（列数不变，绝不会切字）
  final totalScale =
      displayWidth(labels.labelTotal) + 1 + totalAmountW <=
              TicketScale.xlarge.columnsFor(cols)
          ? TicketScale.xlarge
          : TicketScale.large;
  final totalCols = totalScale.columnsFor(cols);
  rows.add(TicketRow.bold(
    padRight(_truncateToWidth(labels.labelTotal, totalCols - totalAmountW),
            totalCols - totalAmountW) +
        totalText,
    totalScale,
  ));
  rows.add(TicketRow(divider));

  // ---- 支付方式 / 实收 / 找零 ----
  if (r.paymentMethodLabel.isNotEmpty && r.paymentMethodLabel != '-') {
    rows.add(TicketRow(
        _truncateToWidth('${labels.labelPay}: ${r.paymentMethodLabel}', cols)));
  }
  for (final extra in r.extraLines) {
    rows.add(TicketRow(_truncateToWidth(extra, cols)));
  }
  rows.add(TicketRow(''));
  if (r.thankyou.trim().isNotEmpty) {
    rows.add(TicketRow(padCenter(_truncateToWidth(r.thankyou.trim(), cols), cols)));
  }

  return rows;
}

/// 兼容旧调用（只要文本）：测试和别的地方还在用它。
List<String> buildReceiptLines(ReceiptData r) =>
    buildReceiptRows(r).map((x) => x.text).toList();

/// 把订单排成「厨房单」的**一行行文本 + 每行字号**。
///
/// 版式（58mm / Font A = 32 列，**外卖单**为例）：
///
/// ```text
///          厨师单 1              ← 大（双倍高）：分票用的编号
///     外卖 10-10 13:45           ← **特大**（双倍宽高）：票面上最大的一行 = 哪桌/哪个外卖 + 时间
///           张三                 ← 特大：外卖的名字（没名字就打系统给的号 `#3`）
///        等待 20 分钟             ← 特大：只有电话外卖填了等待时间才有
///                                 ← 空一行，分块
/// - - - - - - - - - - - - - - - - ← 虚线（普通字号、整张纸宽）
/// 数量  菜名                       ← 普通：表头
/// 2     牛肉炒饭                   ← 菜品：**特大**（[kKitchenItemScale]），**菜名在数量右边居中**
///   加辣                          ← 普通：选项（一条一行、缩进）
///   不要香菜                       ← 普通：备注（一条一行、缩进；太长自动折行，**不截断**）
/// - - - - - - - - - - - - - - - -
/// ```
///
/// 三条要点：
/// 1. **菜品区是主体**：顶部只有几行（标题 / 地点时间 / 名字 / 分隔线），其余全是菜；
/// 2. 「厨师单 1 / 2」是[KitchenData.copyIndex]，和 [KitchenData.copyTotal] 一起决定；
/// 3. **每一行按自己的字号算列数**：普通字号的行用纸张原始列数（[receiptColumns]），
///    放大的行用 [TicketScale.columnsFor] 换算（双倍宽 → 列数减半）。
///    [_headline] 已经把「特大放不下就退回大」处理好了。
///
/// 菜品行是**数量在左、菜名在右（居中）**：厨房先看份数，再看是什么菜。
/// 菜名一个放不下会**折到下一行**（整行居中），不会截断。
///
/// 想自己调版式：直接改这个函数里的 add 顺序/内容就行，见 `kitchen_ticket.md`。
List<TicketRow> buildKitchenRows(KitchenData k) {
  // ⚠️ 这里是**纸张原始列数**（58mm = 32、80mm = 48）；每一行再按**自己的字号**
  // 用 [TicketScale.columnsFor] 换算能放多少列。**不要**在这里先按菜品字号缩一遍 ——
  // 那样虚线 / 选项 / 备注这些**普通字号**的行会被当成半宽，菜品行还会被缩两次
  // （特大档下菜名只剩 3 列，就是以前"餐品挤成一团、没利用空间"的原因）。
  final cols = receiptColumns(k.paperWidth);
  final labels = k.labels;
  final rows = <TicketRow>[];

  // ---- ① 标题：厨师单 1 / 厨师单 2（**大**）----
  // 编号是分票用的，「大」就够；票面上最大的一行是下面「哪桌 / 哪个外卖 + 时间」。
  final title = <String>[
    labels.title,
    if (k.copyTotal > 1) '${k.copyIndex}',
    if (k.isAppend) labels.append,
  ].join(' ');
  rows.add(_headline(title, cols, preferred: TicketScale.large));

  // ---- ② 「外卖 10-10 13:45」：**票面上最大的一行**（特大）----
  // 左边「哪桌 / 外卖」、右边时间。太长（电话外卖、堂食带桌号）就退回「大」，不会被切。
  final where = k.table.isNotEmpty
      ? '${labels.labelTable} ${k.table}'
          '${k.typeLabel.isEmpty ? '' : ' · ${k.typeLabel}'}'
      : k.typeLabel; // 外卖没有桌号，就打「外卖」
  final when = kitchenTime(k.createdAt);
  final whereScale = _headlineScale('$where $when', cols);
  final whereCols = whereScale.columnsFor(cols);
  final whereW = whereCols - displayWidth(when) - 1; // 右边留给时间，中间空一格
  rows.add(TicketRow(
    '${padRight(_truncateToWidth(where, whereW), whereW)} $when',
    whereScale,
  ));

  // ---- ③ 外卖 / 电话外卖：**名字（没名字就打系统给的号）**（特大）----
  // 堂食看桌号就够；外卖只能靠名字 / 号喊单（尤其电话外卖，客人报的就是名字 / 号）。
  if (k.isTakeaway) {
    final who = k.orderLabel.trim().isNotEmpty
        ? k.orderLabel.trim()
        : (k.dailyNo > 0 ? '#${k.dailyNo}' : ''); // 老数据可能既没名字也没号 → 这行不打
    if (who.isNotEmpty) rows.add(_headline(who, cols));
  }

  // ---- ④ 电话外卖：**要等多久**（同样特大号 —— 厨房一眼就看到，别漏了）----
  if (k.waitMinutes > 0 && labels.wait.isNotEmpty) {
    rows.add(_headline('${labels.wait} ${k.waitMinutes} ${labels.minutes}', cols));
  }

  rows.add(TicketRow('')); // 空一行：顶部信息和菜品区之间透口气（参考图也是这样分块的）
  rows.add(TicketRow('- ' * (cols ~/ 2)));

  // ---- ⑤ 菜品（票面主体）：**数量在左、菜名居中**、字号**特大** ----
  // 厨房先扫一眼「几份」，再看是什么菜 —— 数量列固定在最左边；
  // 菜名在剩下的地方**居中**（原来左对齐，挤在数量旁边、右边空一大片）。
  final itemScale = kKitchenItemScale;
  // 菜品行能用的列数（特大 = 双倍宽）：58mm = 16、80mm = 24
  final itemCols = kitchenItemColumns(k.paperWidth);
  final qtyW = itemCols >= 32 ? 6 : 5;
  final nameW = itemCols - qtyW;

  // 菜品加粗（`kKitchenBoldItemNames`）：加粗 + 放大，厨房隔着两米也看得清。
  TicketRow itemRow(String text) => kKitchenBoldItemNames
      ? TicketRow.bold(text, itemScale)
      : TicketRow(text, itemScale);

  // 表头：**普通字号**、整张纸宽（数量在左、菜名在右）
  rows.add(TicketRow(
      padRight(_truncateToWidth(labels.colQty, 5), 6) +
          _truncateToWidth(labels.colName, cols - 6)));

  for (final l in k.lines) {
    // 数量列留最后 1 列当空隙（`qtyW - 1`），保证数量再长也不会和菜名粘在一起
    final qty = padRight(_qtyCell(l, qtyW - 1), qtyW);
    // 菜名在数量右边居中；一个放不下就**折到下一行**（整行居中），一个字都不丢。
    // ⚠️ 用 `displayName`：**厨师单看昵称**（顾客小票那边用的才是全名 `name`）。
    final name = _wrapToWidth(kitchenItemName(l.displayName), nameW);
    rows.add(itemRow(qty + padCenter(name.first, nameW)));
    for (final more in name.skip(1)) {
      rows.add(itemRow(padCenter(more, itemCols)));
    }
    // 选项 / 备注：**普通字号**（整张纸宽）、**一条一行**、太长自动折行 —— 绝不截断
    for (final d in _detailLines(l, cols)) {
      rows.add(TicketRow(d));
    }
  }

  rows.add(TicketRow('- ' * (cols ~/ 2)));
  return rows;
}

/// 菜品下面那几行「选项 / 备注」：**一条一行**、缩进 2 列、太长自动折行（**不截断**）。
///
/// 以前是「选项 + 备注」拼成一行再按纸宽截断 —— 备注排在最后，
/// 一超长整条就被 cut（厨房看不到「不要香菜」这种要紧的话）。
List<String> _detailLines(OrderLine l, int cols) {
  const indent = '  ';
  final w = cols - indent.length;
  final out = <String>[];
  if (l.options.isNotEmpty) {
    for (final s in _wrapToWidth(l.options.join(' / '), w)) {
      out.add('$indent$s');
    }
  }
  for (final n in l.notes) {
    final t = n.trim();
    if (t.isEmpty) continue;
    for (final s in _wrapToWidth(t, w)) {
      out.add('$indent$s');
    }
  }
  return out;
}

/// 按**显示列宽**折行（中文算 2 列）：一行放不下就换行，**一个字都不丢**。
///
/// 断点：优先在这一行的**最后一个空格**处断（西文菜名 / 备注好看一点，空格本身丢掉），
/// 没空格（中文）就按字符硬断。整行连一个字都放不下（纸太窄）时不折，原样返回。
List<String> _wrapToWidth(String s, int width) {
  final out = <String>[];
  var rest = s;
  while (width > 0 && displayWidth(rest) > width) {
    final runes = rest.runes.toList();
    var w = 0;
    var cut = 0; // 这一行能放几个字符
    var space = -1; // 最后一个空格在哪
    for (var i = 0; i < runes.length; i++) {
      final cw = _isWide(runes[i]) ? 2 : 1;
      if (w + cw > width) break;
      w += cw;
      cut = i + 1;
      if (runes[i] == 0x20) space = i;
    }
    if (cut == 0) break; // 一个字都放不下 → 别再折腾
    final at = space > 0 ? space : cut;
    out.add(String.fromCharCodes(runes.take(at)));
    rest = String.fromCharCodes(runes.skip(at == space ? at + 1 : at));
  }
  // 空字符串也要返回一行（调用方会取 `first`）
  if (rest.isNotEmpty || out.isEmpty) out.add(rest);
  return out;
}

/// 顶部那种**大字标题行**：一律**居中**，字号见 [_headlineScale]。
///
/// 用它的是这四行：「厨师单 1 / 2」（[preferred] = 大）、
/// **外卖的名字 / 号**、**「哪桌 / 外卖 + 时间」**、电话外卖的**等待时间**（默认特大）。
TicketRow _headline(String text, int cols,
    {TicketScale preferred = TicketScale.xlarge}) {
  final scale = _headlineScale(text, cols, preferred);
  final w = scale.columnsFor(cols);
  return TicketRow(padCenter(_truncateToWidth(text, w), w), scale);
}

/// 大字标题行用哪个字号：
/// - [preferred] 不是特大 → 就用它（标题固定用「大」）；
/// - 要特大 → **放得下才用特大**（[TicketScale.xlarge]，双倍宽 + 双倍高），
///   放不下退回「大」（[TicketScale.large]，只双倍高）——
///   这样既不切字，也不会被打印机自己折成两行。
///
/// 例（58mm = 32 列）：特大一行只有 16 列。
/// 「外卖 10-10 13:45」= 16 列 → 特大；「电话外卖 10-10 13:45」= 20 列 → 退回大。
TicketScale _headlineScale(String text, int cols,
    [TicketScale preferred = TicketScale.xlarge]) {
  if (preferred != TicketScale.xlarge) return preferred;
  return displayWidth(text) <= TicketScale.xlarge.columnsFor(cols)
      ? TicketScale.xlarge
      : TicketScale.large;
}

/// 兼容旧调用（只要文本）：测试和别的地方还在用它。
List<String> buildKitchenLines(KitchenData k) =>
    buildKitchenRows(k).map((r) => r.text).toList();

/// 厨师单上的**时间**：`10-10 13:45`（月-日 时:分）。
///
/// 想换格式（加秒、改成 `dd/MM`、只要时:分…）就改这一行。
String kitchenTime(DateTime dt) =>
    '${_two(dt.month)}-${_two(dt.day)} '
    '${_two(dt.hour)}:${_two(dt.minute)}';

/// 厨师单上的**菜名**：名字以数字结尾、且数字前是字母/空格时，给数字加个 `#`。
///
/// - `Lonche14` → `Lonche #14`
/// - `Lonche 14` → `Lonche #14`
/// - `Taco 3` → `Taco #3`
///
/// 厨师扫一眼就知道是几号，不用在脑子里断词。
/// 不动的：`Coca 600ml`（结尾是字母）、`Lonche14 Grande`（结尾不是数字）、
/// `Pizza 2x1`（数字前面那段里还有数字，多半是"2x1"这种写法，不该被拆）。
///
/// ⚠️ 传进来的名字是**昵称优先**（`OrderLine.displayName`）—— 菜单里有「菜品昵称」
/// 时，厨房单上打的就是昵称；顾客小票用全名（不走这个函数）。
/// 不想要这个规则？把函数体改成 `return name;` 就行。
String kitchenItemName(String name) {
  final m = RegExp(r'^(.*?[A-Za-z\u00C0-\u024F])[ ]?(\d{1,3})$')
      .firstMatch(name.trim());
  if (m == null) return name;
  final head = m.group(1)!.trimRight();
  if (head.isEmpty || RegExp(r'\d').hasMatch(head)) return name;
  return '$head #${m.group(2)}';
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
