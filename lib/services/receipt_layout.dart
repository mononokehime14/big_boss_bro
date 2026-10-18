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

  /// 表头右边那一列「**备注**」（选项 + 特别备注打在这里）。
  ///
  /// 空字符串 = 表头不打这个字（老调用 / 测试里没传），行内容不受影响。
  final String colNote;

  const KitchenLabels({
    required this.title,
    required this.labelTable,
    required this.colName,
    required this.colQty,
    required this.append,
    this.wait = '',
    this.minutes = '',
    this.colNote = '',
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

  /// 票面**最下面那块徽标**上的**西文**（堂食 / 外卖 / 电话外卖，例如 `AQUI` / `LLEVAR`）。
  ///
  /// 徽标就是**两行大字**：西文一行 + 中文一行（见 `buildKitchenRows` ⑤段）——
  /// 西语 / 英语的厨师看西文那行，中文的厨师看中文那行。
  final String badgeWestern;

  /// 徽标上的**中文**（`堂食` / `外卖` / `电话外卖`）。
  ///
  /// ⚠️ 这一行是**固定要打的**（店里有中国厨师，哪怕票面语言选了西语 / 英语）——
  /// 所以它按**强制中文模式**打（`escpos.dart` 的 [gbkLineBytes]），
  /// 哪怕整张票设的是 `cp850` / `latin1` 也不会变成 `?`。
  /// 传空字符串 = 这一行不打（只留西文）。
  final String badgeChinese;

  /// 单子类型的**正式叫法**（`堂食` / `外卖` / `电话外卖`，随票面语言）。
  ///
  /// 用在**门牌**那行：外卖打「外卖 张三」/「外卖 #3」（堂食只打桌号）。
  final String typeLabel;

  /// 是不是**外卖 / 电话外卖**（= `Order.isTakeaway`）。
  ///
  /// true 时：中上部打**外卖的名字**（没名字就打系统给的号 [dailyNo]——
  /// 堂食靠桌号认单，外卖只能靠名字 / 号，厨房才不会拿错）。
  final bool isTakeaway;

  /// **外卖单的名字**（堂食恒为空）。见 `models/order.dart` 的 `Order.label`。
  final String orderLabel;

  /// **当天第几号外卖**（系统给的号，1 起；0 = 老数据没号）。
  ///
  /// 外卖单**没起名字**时，中上部那行大字打的就是它（`#3`）—— 见 `buildKitchenRows` ③段。
  final int dailyNo;

  /// **要等多久（分钟）**：电话外卖填了才有值（0 = 不打这一行）。
  /// 见 `models/order.dart` 的 `Order.waitMinutes`。
  final int waitMinutes;

  /// 这是第几张（1 起）。厨房单通常打两张，票面要能一眼分清。
  final int copyIndex;

  /// 一共打几张（1 = 不打编号）。
  final int copyTotal;

  /// **第一道饮料在第几行**（`-1` = 这张单没有饮料 / 不用分组）。
  ///
  /// 由调用方（`PosController.kitchenTicketLines`）算好：**餐品在前、饮料在后**，
  /// 把饮料那几行的起点告诉排版，见 [buildKitchenRows] ④段 —— 那里会在
  /// 这个下标前面打一条虚线，厨师一眼看出"下面这些是饮料"。
  final int drinksFrom;

  KitchenData({
    required this.table,
    required this.orderId,
    required this.createdAt,
    required this.lines,
    required this.paperWidth,
    required this.labels,
    this.isAppend = false,
    this.badgeWestern = '',
    this.badgeChinese = '',
    this.typeLabel = '',
    this.isTakeaway = false,
    this.orderLabel = '',
    this.dailyNo = 0,
    this.waitMinutes = 0,
    this.copyIndex = 1,
    this.copyTotal = 1,
    this.drinksFrom = -1,
  });
}

/// 小票 / 厨房单里的**一行**：文本 + 这一行自己的字号（可选加粗）。
///
/// 为什么一行一行带字号：一张票上要混几种大小才好看 ——
/// 「厨师单 1 / 时间」用「大」，桌号/名字/等待时间/菜品/选项备注/**底部徽标**用「特大」、
/// 顾客小票的**合计**也是加大加粗（见 `buildReceiptRows`）。
class TicketRow {
  final String text;
  final TicketScale scale;

  /// 这一行要不要加粗：厨房单的**菜品行**看 `escpos.dart` 的 `kKitchenBoldItemNames`；
  /// 小票的**合计行**恒定加粗。
  final bool bold;

  /// **原始字节行**（已经编好的 ESC/POS 指令）：不为 null 时 [text] 会被忽略，
  /// `escpos.dart` 把这些字节**原样发出去**（它见 `TicketLine.raw` 走同一条路）。
  ///
  /// 现在只有一个用处：厨师单的"**空半行**"—— 只发一条 `ESC J n` 走纸、不打字，
  /// 见 [kKitchenBlankRowDots]。
  final List<int>? raw;

  /// true = 这一行**不换行**：下一行接着打在同一行上。
  ///
  /// 用处：厨师单的菜品行 = 「数量 + 菜名」（**加粗**）紧接着「备注」（**不加粗**），
  /// 同一行里混字重（见 [TicketRow.head] / [TicketRow.headBold]）。
  final bool continueLine;

  const TicketRow(this.text, [this.scale = TicketScale.normal])
      : bold = false,
        raw = null,
        continueLine = false;

  /// 加粗版（菜品行、小票合计用它）。
  const TicketRow.bold(this.text, [this.scale = TicketScale.normal])
      : bold = true,
        raw = null,
        continueLine = false;

  /// **只走纸、不打字**的一行（原始字节，例如 `ESC J 20`）：
  /// 厨师单的"空半行"用它，见 [kKitchenBlankRowDots]。
  const TicketRow.feed(this.raw, [this.scale = TicketScale.normal])
      : text = '',
        bold = false,
        continueLine = false;

  /// **自带文字的原始字节行**：[text] 只是给测试 / 屏幕预览看的，
  /// 真正打出去的是 [raw]（例如"强制中文模式"的那一行，见 `escpos.dart` 的 `gbkLineBytes`）。
  ///
  /// [bold] 只是**标注**（raw 行不走通用的加粗包）：真正的 `ESC E 1` 由调用方
  /// 编进 [raw] 里（厨师单底部徽标那两行就是这么加的粗）。
  ///
  /// ⚠️ [scale] / [bold] 都是**命名参数**（Dart 不允许同时有可选位置参数和命名参数）。
  const TicketRow.bytes(this.text, this.raw,
      {this.scale = TicketScale.normal, this.bold = false})
      : continueLine = false;

  /// **不换行的前半段**（不加粗）：下一行接着打在同一行上。
  const TicketRow.head(this.text, [this.scale = TicketScale.normal])
      : bold = false,
        raw = null,
        continueLine = true;

  /// **不换行的前半段**（**加粗**）：厨师单「数量 + 菜名」用它，
  /// 后面紧跟一条不加粗的 `TicketRow` 打「备注」。
  const TicketRow.headBold(this.text, [this.scale = TicketScale.normal])
      : bold = true,
        raw = null,
        continueLine = true;
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
/// ⚠️ 只适用于**特大字号的行**（菜品 / 桌号 / 底部徽标）。
/// 普通字号的行（虚线 / 表头）要用 [receiptColumns]（纸张原始列数），
/// 别拿这个去截它们 —— 那会白白浪费半张纸。
int kitchenItemColumns(String paperWidth) => receiptColumns(paperWidth) ~/ 2;

// ---------------------------------------------------------------------------
// 厨师单各段的字号（都写死在代码里，设置页里没有这些项）
// ---------------------------------------------------------------------------

/// 「厨师单 1 / 2」：分票用的编号，**大**就够（票面上最大的是下面那几行）。
const TicketScale kKitchenTitleScale = TicketScale.large;

/// 时间「10-10 13:45」：**大**、居中。
///
/// 厨师不太看时间，所以它排在标题下面（纸的最上面是**别针区**，见
/// [kKitchenTopBlankRows]），字号只给「大」—— 把眼睛留给桌号 / 菜名。
const TicketScale kKitchenTimeScale = TicketScale.large;

/// 「桌号 5」/「张三」/「#3」/「等待 20 分钟」：**特大**（票面上最大的字）。
///
/// 这一段是票面的"门牌"：堂食靠桌号认单，外卖靠名字 / 号喊单。
const TicketScale kKitchenWhoScale = TicketScale.xlarge;

/// 选项 / 备注（「加辣」「不要香菜」）：**大**（双倍高、单倍宽），**不加粗**。
///
/// 比菜名小一档：「点名要的话」要看得到，但不能压过菜名。
/// 第一条跟在菜名右边（同一行），剩下的**一条一行**从最左边打
/// （见 `buildKitchenRows` ④段）。
///
/// 💡 「大」是**单倍宽**，所以备注列能用的列数是普通列数（58mm = 8 列），
/// 不是菜品行那种半宽的 16 列。
const TicketScale kKitchenDetailScale = TicketScale.large;

/// 菜品行里「**数量**」占几列（**特大字号下的列数**）。
///
/// 默认 4：`2` / `12` / `2 份` 都放得下（单位太长就只打数字，见 `_qtyCell`）。
/// 数字**右对齐**在这一列里。
const int kKitchenQtyColumns = 4;

/// 菜品行里「**备注**」占几列的除数：备注列 = 整行 ÷ 这个数。
///
/// 58mm（特大一行 16 列）→ 4 列；80mm（24 列）→ 6 列。
/// - 想让**菜名更宽敞** → 把这个数调**大**（备注列更窄，备注更容易折到下一行）；
/// - 想给**备注更多地方** → 调**小**（3 = 备注占 1/3、菜名只剩一半）。
///
/// ⚠️ 这只是**默认**宽度：第一个「定制项 / 备注」比它长的时候会自动**借菜名的地方**
/// （最多借到菜名只剩 [kKitchenMinNameColumns] 列），好让它留在菜品那一行的右边缘上。
const int kKitchenNoteColumnsDivisor = 4;

/// 菜品行里「**菜名**」列**最少**留几列（**特大列**）：默认 4（= 8 个普通列宽）。
///
/// 右边的「第一个定制项 / 备注」太长时，会从这里借地方（借到只剩这么多为止）；
/// 再长就整条挪到菜品下面去（不劈字、不丢字）。
const int kKitchenMinNameColumns = 4;

/// 底部「外卖 / 堂食」徽标（**西文一行 + 中文一行**）：**最大 + 加粗**。
///
/// 用 [TicketScale.huge]（双倍宽 + **三倍**高）—— 比菜品行的「特大」再高一点，
/// 票面插在杆子上时露在外面的就是这两行，越大越好认。
/// 万一某台打印机不认三倍高，把它改回 [TicketScale.xlarge] 即可。
const TicketScale kKitchenBadgeScale = TicketScale.huge;

/// 厨师单**顶部先空几行**（默认 1 行）。
///
/// 厨师会把单子**别在 / 插在**杆子上，最上面一两厘米是看不见的 ——
/// 所以票面最上面先空几行，把要紧的字（桌号 / 菜名）顶到看得见的地方。
/// 0 = 不留白；想更松就加大（每行约 4~5mm）。
const int kKitchenTopBlankRows = 1;

/// 厨师单上**"空一行"到底空多高**（点数；1 点 ≈ 0.125mm @203dpi）。
///
/// - **`0` = 老老实实打一个空行**：高度 = 字高 + 行距 + [kKitchenExtraFeedDots]，
///   大概 40 点左右（≈5mm），一块一块很清楚；
/// - **`>0`（当前 `20`）= 改成"只走纸这么多点"**（`ESC J n`，一个字都不打）——
///   这就是**空半行**：`20` ≈ 半行、`10` ≈ 1/4 行、`30` ≈ 3/4 行。
///   想让整张票紧凑一截就调这个数。
///
/// ⚠️ 只管**厨师单**（`buildKitchenRows` 里所有"空一行"都用 [_blankRow]）；
/// 顾客小票 / 日结不受影响。
const int kKitchenBlankRowDots = 20;

/// 厨师单上的一行"空行"：见 [kKitchenBlankRowDots]。
///
/// `kKitchenBlankRowDots <= 0` → 普通空行（打一个空串，走正常行高）；
/// `> 0` → 原始字节行，只发 `ESC J n` 走纸，**想空多少点就空多少点**。
TicketRow _blankRow() => kKitchenBlankRowDots <= 0
    ? const TicketRow('')
    : TicketRow.feed(feedDots(kKitchenBlankRowDots));

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
    // 第一行：**只打菜名 + 金额**。
    // 选项 / 备注**不再塞进括号**跟在菜名后面（括号一长就整行被截断，
    // 客人看不清自己点的到底是哪一款），改成下面一条一行地打。
    rows.add(TicketRow(
        padRight(_truncateToWidth(l.name, labelW - 1), labelW) +
            padLeft('${r.currency}${l.subtotal.toStringAsFixed(2)}', amountW)));
    // 第二行：`1 x  $140.00`（有单位就写 `2 份 x $28.00`）
    // ⚠️ 单价用**实收单价**（含备注加价，例如「换炒饭 +70」），这样
    //    「数量 × 单价」跟右边那一行的金额才对得上。
    final unit = l.unit.trim();
    final qty = unit.isEmpty ? '${l.quantity}' : '${l.quantity} $unit';
    rows.add(TicketRow(_truncateToWidth(
        '$qty x  ${r.currency}${l.effectiveUnitPrice.toStringAsFixed(2)}',
        cols)));
    // 定制项：**一条一行**、缩进两格（放不下按整张纸宽折行，不切字）
    for (final opt in l.options) {
      final t = opt.trim();
      if (t.isEmpty) continue;
      for (final s in _wrapToWidth('  $t', cols)) {
        rows.add(TicketRow(s));
      }
    }
    // 特别备注：**一条一行**、缩进两格；带加价的把价签也写出来（`换炒饭 +70`），
    // 客人一眼看得出这钱加在哪。
    for (var n = 0; n < l.notes.length; n++) {
      if (l.notes[n].trim().isEmpty) continue;
      for (final s in _wrapToWidth('  ${l.noteLabelAt(n)}', cols)) {
        rows.add(TicketRow(s));
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
///                                 ← 空 1 行：**别针区**（[kKitchenTopBlankRows]）
///          厨师单 1                ← 大（双倍高）：分票用的编号
///        10-10 13:45               ← 大：时间
///          外卖 张三               ← **特大**：门牌 —— 堂食只打桌号（`桌号 3`）；
///        等待 20 分钟               ←        外卖打「外卖 + 名字/`#号`」；电话外卖再打一行等待时间
///                                 ← 空一行，分块
/// - - - - - - - - - - - - - - - - ← 虚线（普通字号、整张纸宽）
///    数量      菜名      备注       ← 普通：表头（菜名居中、备注居右）
///   2     牛肉炒饭   加辣          ← 菜品：**特大**，数量(右对齐·加粗) | 菜名(居中·加粗) | **第一条**备注(大、不加粗)
///  poner salsa aparte             ← 剩下的备注 → **一条一行、从最左边**（大、不加粗、不丢字）
///                                 ← 空一行，下一道菜
/// - - - - - - - - - - - - - - - -
///                                 ← 空一行
///          LLEVAR                 ← **最大**字号的**西文**
///           外卖                  ← **最大**字号的**中文**（⚠️ 强制中文模式，选西语/英语也照打）
/// ```
///
/// 四条要点：
/// 1. **顶部 = 别针区**：厨师会把单子别在杆子上，所以票面最上面先空 1 行
///    （[kKitchenTopBlankRows]），接着才是**不太要紧**的信息（编号 + 时间）；
/// 2. **紧接着是"门牌"**：堂食打桌号、外卖打「外卖 名字/号」、电话外卖再加一行
///    等待时间，**特大**、居中，不再跟时间之间空行（票面上半截要短）；
/// 3. **菜品区是主体**：一行三列「数量 | 菜名 | 备注」（列宽见
///    [kKitchenQtyColumns] / [kKitchenNoteColumnsDivisor]）：
///    **第一条**备注跟在菜名右边，**剩下的每一条单独一行**从最左边打；
/// 4. **底部是徽标**：**西文 + 中文**各一行，**最大**字号（[kKitchenBadgeScale]）——
///    单子插在杆上时露出来的正好是这一块。中文那行是**固定的**（哪怕票面语言是
///    西语 / 英语、哪怕整张票设的是 `cp850` 也一样出中文，见 [_badgeRows]）。
///    （以前这儿还有一段 ASCII 图案，实测厨师不看、还占好几行纸，已经去掉；
///    想加回来就在 [_badgeRows] 里往这两行前面插 `TicketRow`。）
///
/// **每一行按自己的字号算列数**：普通字号的行用纸张原始列数（[receiptColumns]），
/// 放大的行用 [TicketScale.columnsFor] 换算（双倍宽 → 列数减半）。
/// [_headline] 已经把"放不下就自动降一档"处理好了（特大 → 大 → 普通），
/// 所以**任何一行都不会被切字**。
///
/// 想自己调版式：直接改这个函数里的 add 顺序/内容就行，见 `kitchen_ticket.md`。
List<TicketRow> buildKitchenRows(KitchenData k) {
  // ⚠️ 这里是**纸张原始列数**（58mm = 32、80mm = 48）；每一行再按**自己的字号**
  // 用 [TicketScale.columnsFor] 换算能放多少列。**不要**在这里先按菜品字号缩一遍 ——
  // 那样虚线 / 表头这些**普通字号**的行会被当成半宽，菜品行还会被缩两次
  // （特大档下菜名只剩 3 列，就是以前"餐品挤成一团、没利用空间"的原因）。
  final cols = receiptColumns(k.paperWidth);
  final labels = k.labels;
  final rows = <TicketRow>[];

  // ---- ⓪ 顶部留白：**别针区**（夹子 / 针扎的地方，见 kKitchenTopBlankRows）----
  for (var i = 0; i < kKitchenTopBlankRows; i++) {
    rows.add(_blankRow());
  }

  // ---- ① 标题：厨师单 1 / 厨师单 2（**大**）----
  // 编号是分票用的，排在别针区下面；时间在它下面。这两行都不算要紧。
  final title = <String>[
    labels.title,
    if (k.copyTotal > 1) '${k.copyIndex}',
    if (k.isAppend) labels.append,
  ].join(' ');
  rows.add(_headline(title, cols, preferred: kKitchenTitleScale));

  // ---- ② 时间：`10-10 13:45`（**大**、居中）----
  rows.add(_headline(kitchenTime(k.createdAt), cols,
      preferred: kKitchenTimeScale));

  // ---- ③ 门牌：桌号 / 外卖的名字（没名字就是系统给的号）+ 等待时间（**特大**）----
  // 这一段是票面上最大的一块：堂食靠桌号认单，外卖靠名字 / 号喊单。
  // 「堂食 / 外卖」这四个字搬到票面**最下面**（西文 + 中文徽标），这里只留最要紧的。
  // ⚠️ 它**紧跟时间**（中间不空行）：票面上半截越短，菜和徽标就越大。
  final who = _whoText(k);
  if (who.isNotEmpty) {
    rows.add(_headline(who, cols, preferred: kKitchenWhoScale));
  }
  // 外卖 / 电话外卖：**要等多久**（跟名字同一档字号 —— 厨房一眼就看到，别漏了）
  if (k.waitMinutes > 0 && labels.wait.isNotEmpty) {
    rows.add(_headline('${labels.wait} ${k.waitMinutes} ${labels.minutes}',
        cols,
        preferred: kKitchenWhoScale));
  }
  rows.add(_blankRow()); // 空一行：顶部信息和菜品区之间透口气（参考图也是这样分块的）

  rows.add(TicketRow(_dash(cols)));

  // ---- ④ 菜品（票面主体）：**数量 | 菜名 | 备注** 三列，字号**特大** ----
  // 一行的样子（58mm 特大一行只有 16 列）：
  // ```
  //  2      牛肉炒饭           加辣    ← 数量**贴最左**、菜名居中（特大加粗）| 第一条（大、不加粗）**贴最右**
  //  不要香菜                        ← 剩下的：一条一行、从最左边（大、不加粗）
  // ```
  // 「右边那一条」= **定制项和特别备注里的第一个**（定制项优先）；
  // 没有定制项时，它自然就是第一条特别备注 —— 照样跟在菜名右边、贴右边缘。
  final itemScale = kKitchenItemScale;
  // 菜品行能用的列数（特大 = 双倍宽）：58mm = 16、80mm = 24
  final itemCols = kitchenItemColumns(k.paperWidth);
  // 三列：数量[固定] + 菜名[剩下] + 备注[整行 ÷ kKitchenNoteColumnsDivisor]
  // ⚠️ 用 [_clampInt] 而不是 `.clamp()`：`clamp` 的静态返回类型是 `num`，
  //    后面拿去做列宽（int）会编译不过。
  final qtyW = _clampInt(kKitchenQtyColumns, 1, itemCols - 2);
  final noteWXl = _clampInt(itemCols ~/ kKitchenNoteColumnsDivisor, 1,
      itemCols - qtyW - 2); // 至少给菜名留 2 列
  final nameW = itemCols - qtyW - noteWXl;
  // 备注是**「大」字号**（单倍宽），所以它能用的列数是普通列数：
  //   数量+菜名 占 `qtyW + nameW` 个特大列 = 它们的**两倍**普通列，剩下的全给备注。
  //   默认宽：58mm 32 - 2×12 = **8 列**；80mm 48 - 2×18 = **12 列**。
  //   （每一行的实际宽会在下面按「第一个定制项 / 备注」的长度重算 —— 太长就从菜名借）
  // 备注列**最多能长多宽**：把菜名压到 [kKitchenMinNameColumns] 之后剩下的都给它。
  // 这样「第一个定制项 / 备注」长一点时，宁可**借菜名的地方**也要挤在同一行的
  // 右边缘上（而不是掉到下面一行、看着跟这道菜没关系）。
  final minNameW = _clampInt(kKitchenMinNameColumns, 1, nameW);
  final maxNoteW = cols - 2 * (qtyW + minNameW);

  // 菜品加粗（`kKitchenBoldItemNames`）：加粗 + 放大，厨房隔着两米也看得清。
  TicketRow itemRow(String text) => kKitchenBoldItemNames
      ? TicketRow.bold(text, itemScale)
      : TicketRow(text, itemScale);

  // 「数量 + 菜名」那一段（**加粗**）：后面紧跟「第一个定制项 / 备注」（同一行、不加粗）
  TicketRow itemHead(String text) => kKitchenBoldItemNames
      ? TicketRow.headBold(text, itemScale)
      : TicketRow.head(text, itemScale);

  // 表头：**普通字号**（列数正好是特大下的两倍）：
  // **数量贴左**、菜名居中（跟下面的菜名对齐）、**备注贴右**。
  final hQtyW = qtyW * 2;
  final hNoteW = noteWXl * 2;
  final hNameW = cols - hQtyW - hNoteW;
  rows.add(TicketRow(
      padRight(_truncateToWidth(labels.colQty, hQtyW), hQtyW) +
          padCenter(_truncateToWidth(labels.colName, hNameW), hNameW) +
          padLeft(_truncateToWidth(labels.colNote, hNoteW), hNoteW)));

  for (var i = 0; i < k.lines.length; i++) {
    final l = k.lines[i];
    // ---- 饮料分界：餐品打完了，饮料从这一行开始 → 先打一条虚线 ----
    // （行是调用方排好的：餐品在前、饮料在后；[KitchenData.drinksFrom] 就是饮料的起点）
    if (i == k.drinksFrom && i > 0) {
      rows.add(TicketRow(_dash(cols)));
    }
    // 数量**贴最左**（`2` / `12` / `2 份` 都从纸的左边缘开始）
    final qty = padRight(_qtyCell(l, qtyW), qtyW);
    // 「第一个」= 定制项在前，没有定制项才用第一条特别备注
    final notes = _noteItems(l);
    String noteHead = '';
    var noteRest = notes;
    if (notes.isNotEmpty && displayWidth(notes.first) <= maxNoteW) {
      noteHead = notes.first;
      noteRest = notes.sublist(1);
    }
    // 菜名列 = 整行 − 数量列 − 备注列；
    // 「第一个」太长时**从菜名这里借地方**（最多借到只剩 [kKitchenMinNameColumns] 列），
    // 好让它留在菜品这一行的右边缘上（不用借就还是默认宽度，表头才对得齐）。
    final need = noteHead.isEmpty ? 0 : displayWidth(noteHead);
    final fitting = (cols - 2 * qtyW - need) ~/ 2;
    final nameCols = noteHead.isEmpty
        ? itemCols - qtyW
        : _clampInt(fitting < nameW ? fitting : nameW, minNameW, itemCols - qtyW);
    // 备注列宽 = 剩下的普通列（这样「第一个」正好顶到纸的右边缘，中间不留缝）
    final headNoteW = noteHead.isEmpty ? 0 : cols - 2 * (qtyW + nameCols);
    // 菜名在中间那一列**居中**；一个放不下就**折到下一行**（整行居中），一个字都不丢。
    // ⚠️ 用 `displayName`：**厨师单看昵称**（顾客小票那边用的才是全名 `name`）。
    final name = _wrapToWidth(kitchenItemName(l.displayName), nameCols);

    final head = qty + padCenter(name.first, nameCols);
    if (noteHead.isNotEmpty) {
      // 同一行：前半段（数量+菜名，特大加粗、不换行）+ 后半段（第一个备注，大、不加粗）
      rows.add(itemHead(head));
      // **贴右边缘**：前面垫空格，让这一条正好顶到纸的右边
      final padN = headNoteW - displayWidth(noteHead);
      rows.add(TicketRow(
          '${padN > 0 ? ' ' * padN : ''}$noteHead', kKitchenDetailScale));
    } else {
      // 没有选项也没有备注（或者第一条长到放不下）：整行还是**铺满**
      rows.add(itemRow(padRight(head, itemCols)));
    }
    // 菜名放不下 → 折到下一行（整行居中）
    for (final more in name.skip(1)) {
      rows.add(itemRow(padCenter(more, itemCols)));
    }
    // 剩下的备注 → **一条一行、从最左边**打（大、不加粗；一条太长就按整张纸宽折）
    for (final item in noteRest) {
      for (final s in _wrapToWidth(item, cols)) {
        rows.add(TicketRow(s, kKitchenDetailScale));
      }
    }
    // 菜品之间空一行：一道菜一块，厨师扫的时候不会串行（跟顾客小票一样）
    if (i != k.lines.length - 1) rows.add(_blankRow());
  }

  rows.add(TicketRow(_dash(cols)));

  // ---- ⑤ 底部徽标：**西文 + 中文**（票面上最大的一块）----
  // 单子插在杆子上时，露在外面的就是这一块 —— 所以"堂食还是外卖"放在这里，
  // 只有两行大字，不再画图案（图案实测没用还费纸）。
  rows.addAll(_badgeRows(k));

  return rows;
}

/// 虚线：`- - - -`（整张纸宽，普通字号）。
String _dash(int cols) => '- ' * (cols ~/ 2);

/// `int` 版的夹取：`x < lo → lo`，`x > hi → hi`，否则原样。
///
/// 为什么不用 `.clamp()`：它声明的返回类型是 `num`，拿去做列宽（要 `int`）会编译不过。
int _clampInt(int x, int lo, int hi) => x < lo ? lo : (x > hi ? hi : x);

/// 「门牌」那行打什么（**特大字、居中**）：
/// - **外卖 / 电话外卖**：有名字打名字，没名字打系统给的号（`#3`）；
/// - **堂食**：`桌号 5`（[KitchenLabels.labelTable] + 桌号）。
String _whoText(KitchenData k) {
  if (k.isTakeaway) {
    final label = k.orderLabel.trim();
    final who = label.isNotEmpty
        ? label
        : (k.dailyNo > 0 ? '#${k.dailyNo}' : ''); // 老数据可能既没名字也没号
    if (who.isEmpty) return k.typeLabel; // 啥都没有就只打「外卖」
    // 「外卖 张三」：类型在最前面，厨房一眼看出这是要打包走的单
    return k.typeLabel.isEmpty ? who : '${k.typeLabel} $who';
  }
  final table = k.table.trim();
  if (table.isEmpty) return '';
  return k.labels.labelTable.isEmpty
      ? table
      : '${k.labels.labelTable} $table';
}

/// 底部徽标：**西文一行 + 中文一行**（都是**最大**字号），上面空一行跟菜品分开。
///
/// 以前这儿还画过 ASCII 图案（堂食画桌子、外卖画打包袋）—— **实测厨师不看**，
/// 而且占掉三四行纸，所以去掉了，只留字。
/// 想加回来很简单：在两行字前面补一句
/// `out.add(TicketRow(padCenter(图案行, kKitchenBadgeScale.columnsFor(cols)), kKitchenBadgeScale));`
/// 就行（图案只能是纯 ASCII、宽度 ≤ 16 列，见 `kitchen_ticket.md` §5 例④）。
///
/// ⚠️ **中文那行是强制中文模式**打的（[gbkLineBytes]）：整张票哪怕设的是 `cp850`，
/// 这一行也照样出中文 —— 它是"固定要有"的（见 `kitchen_ticket.md` §3.5）。
List<TicketRow> _badgeRows(KitchenData k) {
  final cols = receiptColumns(k.paperWidth);
  final out = <TicketRow>[_blankRow()]; // 空一行，跟菜品分开

  final western = k.badgeWestern.trim();
  if (western.isNotEmpty) {
    // 西文：**加粗**（跟下面中文那行一致）
    out.add(_headline(western, cols, preferred: kKitchenBadgeScale, bold: true));
  }
  final chinese = k.badgeChinese.trim();
  if (chinese.isNotEmpty) {
    // 中文：**自己进出中文模式**（FS & … FS .），所以不看当前编码是什么。
    // 前面的空格在正常模式里打（不会被当成双宽字），只有那几个汉字进中文模式。
    // 加粗的 `ESC E` 指令**塞进这一行的原始字节里**（raw 行不走通用加粗包）。
    final scale = _headlineScale(chinese, cols, kKitchenBadgeScale);
    final w = scale.columnsFor(cols);
    final text = _truncateToWidth(chinese, w);
    final left = (w - displayWidth(text)) ~/ 2; // 左右居中
    out.add(TicketRow.bytes(
      padCenter(text, w),
      gbkLineBytes(text, scale: scale, leadingSpaces: left, bold: true),
      scale: scale,
      bold: true,
    ));
  }
  return out;
}

/// 这一行要打的**备注条目**：定制项在前，然后每条特别备注（都是单独的字符串）。
///
/// 为什么拆开：第一条要跟在菜名右边（同一行），**剩下的一条一行**从最左边打
/// （见 `buildKitchenRows` ④段）—— 拼成一长串就没法分了。
List<String> _noteItems(OrderLine l) {
  final out = <String>[
    for (final o in l.options)
      if (o.trim().isNotEmpty) o.trim(),
  ];
  for (final n in l.notes) {
    final t = n.trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// 从 [s] 里切出**一行**（显示宽度 ≤ [width]），返回 `(这一行, 剩下的)`。
///
/// 断点：优先在这一行的**最后一个空格**处断（西文菜名 / 备注好看一点，空格本身丢掉），
/// 没空格（中文）就按字符硬断。连一个字都放不下（纸太窄）时返回 `('', s)`。
///
/// 菜品行要"第一段放在行尾的备注列里、剩下的从下一行最左边接"（见 `buildKitchenRows`
/// ④段），所以把"切一行"单独拆出来给 `_wrapToWidth` 和它共用。
(String, String) _takeLine(String s, int width) {
  final runes = s.runes.toList();
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
  if (cut == 0) return ('', s); // 一个字都放不下
  final at = space > 0 ? space : cut;
  return (
    String.fromCharCodes(runes.take(at)),
    String.fromCharCodes(runes.skip(at == space ? at + 1 : at)),
  );
}

/// 按**显示列宽**折行（中文算 2 列）：一行放不下就换行，**一个字都不丢**。
///
/// 断点规则见 [_takeLine]。整行连一个字都放不下（纸太窄）时不折，原样返回。
List<String> _wrapToWidth(String s, int width) {
  final out = <String>[];
  var rest = s;
  while (width > 0 && displayWidth(rest) > width) {
    final (head, tail) = _takeLine(rest, width);
    if (head.isEmpty) break; // 一个字都放不下 → 别再折腾
    out.add(head);
    rest = tail;
  }
  // 空字符串也要返回一行（调用方会取 `first`）
  if (rest.isNotEmpty || out.isEmpty) out.add(rest);
  return out;
}

/// 顶部那种**大字标题行**：一律**居中**，字号见 [_headlineScale]。
///
/// 用它的是这几行：「厨师单 1 / 2」（[kKitchenTitleScale] = 大）、时间、
/// **桌号 / 外卖的名字 / 号**、电话外卖的**等待时间**、以及底部徽标的**西文 / 中文**
/// （徽标是 [TicketScale.huge]）。放不下会自动降一档，不会切字。
///
/// [bold] = true 时整行加粗（徽标那两行用）。
TicketRow _headline(String text, int cols,
    {TicketScale preferred = TicketScale.xlarge, bool bold = false}) {
  final scale = _headlineScale(text, cols, preferred);
  final w = scale.columnsFor(cols);
  final padded = padCenter(_truncateToWidth(text, w), w);
  return bold ? TicketRow.bold(padded, scale) : TicketRow(padded, scale);
}

/// 大字标题行用哪个字号：**从 [preferred] 往下试，放得下就用**。
///
/// 降级链：**超高**（[TicketScale.huge]，双倍宽 + 三倍高）→ **特大**
/// （[TicketScale.xlarge]，双倍宽 + 双倍高）→ **大**（[TicketScale.large]，
/// 只双倍高、列数不变）→ **普通**。
/// 这样既不切字，也不会被打印机自己折成两行。
///
/// 例（58mm = 32 列）：特大一行只有 16 列。
/// 「桌号 5」= 6 列 → 特大；西语名字特别长（> 16 列）→ 大（32 列）；
/// 再长（> 32 列）→ 普通（也放不下才会被 [_truncateToWidth] 截）。
TicketScale _headlineScale(String text, int cols,
    [TicketScale preferred = TicketScale.xlarge]) {
  final width = displayWidth(text);
  var scale = preferred;
  while (width > scale.columnsFor(cols)) {
    switch (scale) {
      case TicketScale.huge:
        scale = TicketScale.xlarge;
      case TicketScale.xlarge:
        scale = TicketScale.large;
      case TicketScale.large:
        scale = TicketScale.normal;
      case TicketScale.normal:
        return scale; // 普通也放不下：交给 _truncateToWidth 截
    }
  }
  return scale;
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
///
/// ⚠️ **整张日结按「特大」打**（跟厨师单的菜品一样大 —— 老板在店里隔着柜台看得清），
/// 所以这里必须按**特大下的列数**排版：特大 = 双倍宽 → 一行只有
/// `receiptColumns() ~/ 2` 列（58mm = **16 列**、80mm = **24 列**）。
/// 字号在 `TicketBuilder.summaryLines()` 里统一设成 [TicketScale.xlarge]。
///
/// 金额列：58mm 给 8 列（`¥1234.50` 就放不下 → 金额另起一行靠右，绝不切数字）；
/// 80mm 给 10 列。
List<String> buildSummaryLines(SummaryData d) {
  final cols = receiptColumns(d.paperWidth) ~/ 2; // 特大：列数减半
  final amountW = cols >= 20 ? 10 : 8;
  final labelW = cols - amountW;
  final lines = <String>[];
  final divider = '=' * cols;
  final thin = '-' * cols;

  /// 「标签 …… 金额」一行。
  ///
  /// 特大下右边那列只有 8~10 列 —— **放不下就分两行**（标签一行、金额靠右一行），
  /// 绝不会把数字截断成 `¥12` 这种（对账时最忌讳这个）。
  void addRow(String label, double amount, {String? symbol}) {
    final s = symbol ?? d.currency;
    final text = '$s${amount.toStringAsFixed(2)}';
    if (displayWidth(label) <= labelW && displayWidth(text) <= amountW) {
      lines.add(padRight(label, labelW) + padLeft(text, amountW));
    } else {
      lines.add(_truncateToWidth(label, cols));
      lines.add(padLeft(text, cols));
    }
  }

  if (d.storeName.isNotEmpty) {
    lines.add(padCenter(_truncateToWidth(d.storeName, cols), cols));
  }
  lines.add(padCenter(_truncateToWidth(d.labels.title, cols), cols));
  lines.add(divider);
  lines.add(_truncateToWidth('${d.labels.date}: ${d.dateLabel}', cols));
  lines.add(thin);

  // 左：堂食 / 外卖（电话外卖有单的时候才多打一行）
  addRow(d.labels.dineIn, d.dineInTotal);
  addRow(d.labels.takeaway, d.takeawayTotal);
  if (round2(d.phoneTakeawayTotal) != 0) {
    addRow(d.labels.phoneTakeaway, d.phoneTakeawayTotal);
  }
  lines.add(thin);

  // 现金分币种
  if (d.cashByCurrency.isEmpty) {
    addRow(d.labels.cash, 0, symbol: d.currency);
  } else {
    d.cashByCurrency.forEach((code, amount) {
      final sym = kCurrencySymbols[code] ?? d.currency;
      final label = code.isEmpty ? d.labels.cash : '${d.labels.cash} $code';
      addRow(label, amount, symbol: sym);
    });
  }
  if (d.cardTotal != 0) addRow(d.labels.card, d.cardTotal);
  if (d.qrTotal != 0) addRow(d.labels.qr, d.qrTotal);
  lines.add(divider);

  // 小计 / 折扣 / 税：有才打（打折或收税的日子才多这几行）
  if (round2(d.discountTotal) != 0 || round2(d.taxTotal) != 0) {
    addRow(d.labels.subtotal, d.subtotalTotal);
    if (round2(d.discountTotal) != 0) {
      addRow(d.labels.discount, d.discountTotal);
    }
    if (round2(d.taxTotal) != 0) addRow(d.labels.tax, d.taxTotal);
    lines.add(thin);
  }

  addRow(d.labels.total, d.total);
  addRow(d.labels.expense, d.expense);
  addRow(d.labels.net, d.total - d.expense);
  lines.add(thin);
  lines.add(_truncateToWidth('${d.labels.orders}: ${d.orderCount}', cols));
  lines.add('');
  return lines;
}
