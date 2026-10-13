import 'dart:convert'; // ascii（行距探测那几行是纯 ASCII，直接编字节最省事）

import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../utils/pricing.dart';
import 'escpos.dart';
import 'receipt_layout.dart';

/// 把订单/设置变成小票的行文本（所有打印通道共用）。
///
/// 小票上的表头文字用 [Settings.receiptLang]（可独立于界面语言）；
/// 菜品名来自菜单/Excel，不翻译。
class TicketBuilder {
  static String _t(Settings s, String key) => L10n.tFor(s.receiptLang, key);

  /// 小票实际生效的语言（''=跟随界面语言）。
  static String _lang(Settings s) =>
      s.receiptLang.isEmpty ? L10n.currentLang : s.receiptLang;

  /// 单子类型在小票 / 厨房单上的文字：堂食 / 外卖 / **电话外卖**。
  static String _typeLabel(Settings s, OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return _t(s, 'order.dineIn');
      case OrderType.takeaway:
        return _t(s, 'order.takeaway');
      case OrderType.phonecallTakeaway:
        return _t(s, 'order.phonecallTakeaway');
    }
  }

  /// 顾客小票（结账时打）：版式照 `assets/receipt_print.jpg` ——
  /// 店头居中 → 「Fecha / Pedido / Empleado / TPV」单头 → 堂食外卖 →
  /// 每道菜「菜名(选项) 金额」+「数量 x 单价」→ 合计 → 支付方式/实收/找零 → 谢谢光临。
  static List<TicketLine> receiptLines(Order order, Settings settings) {
    // 堂食/外卖/电话外卖（桌号打在上面的「单号」那一行里，跟参考小票一样）
    final typeLabel = _typeLabel(settings, order.orderType);

    // 店头（地址 / 电话 / RFC …）：设置里一行一条，居中打印
    final header = settings.storeHeader
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 单头：日期 / 单号（含桌号）/ 收银员 / 终端
    final info = <ReceiptInfoRow>[
      ReceiptInfoRow(_t(settings, 'receipt.labelDate'),
          formatReceiptDateTime(order.createdAt, _lang(settings))),
      ReceiptInfoRow(
        _t(settings, 'receipt.labelOrder'),
        order.table.isEmpty
            ? order.id
            : '${order.id}  ${_t(settings, 'order.table')} ${order.table}',
      ),
      if (order.cashier.isNotEmpty)
        ReceiptInfoRow(_t(settings, 'pay.cashier'), order.cashier),
      if (settings.printerName.isNotEmpty)
        ReceiptInfoRow(_t(settings, 'receipt.labelDevice'), settings.printerName),
    ];

    final extra = <String>[];

    // 外币收款：把币种、汇率、这个币种的应收都打出来（客人要核对）
    if (order.isForeignCurrency) {
      final sym = kCurrencySymbols[order.currencyCode] ?? '';
      extra.add('${_t(settings, 'receipt.currency')}: ${order.currencyCode} '
          '(${_t(settings, 'receipt.rate')} 1 = '
          '${settings.currencySymbol}${_fmtNum(order.exchangeRate)})');
      extra.add('${_t(settings, 'receipt.dueForeign')}: '
          '$sym${order.foreignDue(order.exchangeRate).toStringAsFixed(2)}');
    }

    // 现金：实收 / 找零（用客人付的那个币种计）
    if (order.receivedAmount != null) {
      // 外币用那个币种的符号；本币（汇率 0）用店里设的符号
      final sym = order.isForeignCurrency
          ? (kCurrencySymbols[order.currencyCode] ?? settings.currencySymbol)
          : settings.currencySymbol;
      final code = order.isForeignCurrency ? ' ${order.currencyCode}' : '';
      extra.add('${_t(settings, 'pay.received')}$code: '
          '$sym${order.receivedAmount!.toStringAsFixed(2)}');
      final change = order.changeAmount ?? 0;
      extra.add('${_t(settings, 'pay.change')}$code: '
          '$sym${change.toStringAsFixed(2)}');
    }

    final data = ReceiptData(
      storeName: settings.storeName,
      headerLines: header,
      infoRows: info,
      currency: settings.currencySymbol,
      paymentMethodLabel: _methodLabel(settings, order.paymentMethod),
      lines: order.lines,
      total: order.total,
      thankyou: _t(settings, 'order.thankyou'),
      paperWidth: settings.paperWidth,
      typeLine: typeLabel,
      extraLines: extra,
      amountRows: _amountRows(order, settings),
      labels: ReceiptLabels(
        labelTotal: _t(settings, 'receipt.labelTotal'),
        labelPay: _t(settings, 'receipt.labelPay'),
      ),
    );
    // 小票也是「一行一个字号」：**合计那一行加大加粗**（见 buildReceiptRows）
    return buildReceiptRows(data)
        .map((row) => TicketLine(row.text, scale: row.scale, bold: row.bold))
        .toList();
  }

  /// 去掉多余小数（16 → "16"，18.5 → "18.50"）。
  static String _fmtNum(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2);

  /// 小计 / 折扣 / 税 三行（没打折也没税就不打）。
  static List<ReceiptAmountRow> _amountRows(Order order, Settings settings) {
    if (!order.price.hasAdjustments) return const [];
    final rows = <ReceiptAmountRow>[
      ReceiptAmountRow(_t(settings, 'receipt.labelSubtotal'), order.subtotal),
    ];
    if (order.discountAmount != 0) {
      final pct = order.discountType == DiscountType.percent
          ? ' (${order.discountLabel('')})'
          : '';
      rows.add(ReceiptAmountRow(
        '${_t(settings, 'receipt.labelDiscount')}$pct',
        order.discountAmount,
        negative: true,
      ));
    }
    if (order.taxAmount != 0) {
      final rate = order.taxRate == 0
          ? ''
          : ' (${_fmtNum(order.taxRate)}%)';
      rows.add(ReceiptAmountRow(
        '${_t(settings, 'receipt.labelTax')}$rate',
        order.taxAmount,
      ));
    }
    return rows;
  }

  /// 厨房单（下单/追单时打）：**顶部标「厨师单 1 / 2」+ 桌号/外卖 + 时间，下面全是菜**。
  ///
  /// **外卖 / 电话外卖**在标题下面多打一行**特大字**：外卖单的**名字**
  /// （没起名字就打系统给的号 `#3`）；**电话外卖**再打一行**特大字**的等待时间。
  /// 堂食没有这两行（有桌号就够了）。
  ///
  /// 每行带**自己的字号**（见 `receipt_layout.dart` 的 `buildKitchenRows`）：
  /// 「地点 / 外卖 + 时间」、外卖的名字 / 号、电话外卖的等待时间都是**特大**，
  /// 标题「厨师单 N」是**大**，**菜品行也是特大**（`kKitchenItemScale`，写死的，没有设置项）。
  ///
  /// [copyIndex] / [copyTotal]：这是第几张 / 一共几张。
  /// 默认打两张（一张厨师、一张出餐服务员），份数见 `Settings.kitchenCopies`。
  static List<TicketLine> kitchenLines(
    Order order,
    Settings settings, {
    bool isAppend = false,
    int copyIndex = 1,
    int copyTotal = 1,
  }) {
    final data = KitchenData(
      table: order.table,
      orderId: order.id,
      createdAt: order.createdAt,
      lines: order.lines,
      paperWidth: settings.paperWidth,
      isAppend: isAppend,
      copyIndex: copyIndex,
      copyTotal: copyTotal,
      // 电话外卖填了「等待 N 分钟」→ 厨房单上单独打一行（见 buildKitchenRows）
      waitMinutes: order.waitMinutes,
      typeLabel: _typeLabel(settings, order.orderType),
      // 外卖 / 电话外卖：厨房单顶部要打**名字**（没名字就打系统给的号）——见 ③
      isTakeaway: order.isTakeaway,
      orderLabel: order.label,
      dailyNo: order.dailyNo,
      labels: KitchenLabels(
        title: _t(settings, 'kitchen.title'),
        labelTable: _t(settings, 'order.table'),
        colName: _t(settings, 'kitchen.colName'),
        colQty: _t(settings, 'kitchen.colQty'),
        append: _t(settings, 'kitchen.append'),
        wait: _t(settings, 'kitchen.wait'),
        minutes: _t(settings, 'kitchen.minutes'),
      ),
    );
    return buildKitchenRows(data)
        .map((r) => TicketLine(r.text, scale: r.scale, bold: r.bold))
        .toList();
  }

  /// 日结小票。
  static List<TicketLine> summaryLines(SummaryData data) =>
      buildSummaryLines(data).map((l) => TicketLine(l)).toList();

  /// 测试页（内容已按需求固定）。
  ///
  /// 每一行的用途：
  /// - `----` 刻度尺：长度 = 当前纸宽应有的列数，**应顶到纸的两边**。
  /// - `ASCII` / `Espanol: Gracias`：基本打印 + 西语。
  /// - `中文A(FS&)` / `中文B(ESC t)`：**无视当前编码设置**，强制用两种方式打中文，
  ///   哪一行正常就说明打印机支持中文、且用哪种方式进中文模式。
  /// - `[BIG]`：双倍大小的字。**变大 = ESC/POS 指令真的生效了**（RAW 通道正常）；
  ///   和普通字一样大 = 中间那层（多半是 Windows 驱动）没把指令透传 → 乱码的根源在它。
  /// - `1 normal size` / `2 LARGE` / `3 XLARGE`：**三档字号预览**（`GS ! n`）。
  ///   厨师单的菜品行用的是 **XLARGE（特大）**；哪一行特别大 = 这台机器认得那一档。
  static List<TicketLine> testLines(Settings settings) {
    final cols = receiptColumns(settings.paperWidth);
    final ruler = '-' * cols;
    return <TicketLine>[
      TicketLine(settings.storeName.isEmpty ? 'TEST PAGE' : settings.storeName),
      const TicketLine('------ TEST PAGE ------'),
      TicketLine('Paper ${settings.paperWidth}mm  Cols $cols'),
      TicketLine(
          'Codec ${settings.receiptCodec}  FontA ${settings.useFontA ? 'on' : 'off'}'),
      // 厨师单菜品行固定特大（没有设置项），这里顺便把列数打出来核对排版
      TicketLine('Kitchen items: XLARGE '
          '(${kitchenItemColumns(settings.paperWidth)} cols)'),
      TicketLine(ruler),
      const TicketLine('ASCII  : 0123456789 ABCDEFG'),
      const TicketLine('Espanol: Gracias'),
      TicketLine('中文A(FS&): 恭喜您，打印成功！',
          raw: gbkProbeFs('中文A(FS&): 恭喜您，打印成功！')),
      TicketLine('中文B(ESCt): 恭喜您，打印成功！',
          raw: gbkProbeEscT('中文B(ESCt): 恭喜您，打印成功！')),
      TicketLine('', raw: doubleSizeBytes('[BIG] ESC/POS CHECK')),
      // 三档字号预览（文字故意短，双倍宽也不会超出纸宽）—— 菜品行用的是 XLARGE
      const TicketLine('1 normal size'),
      const TicketLine('2 LARGE', scale: TicketScale.large),
      const TicketLine('3 XLARGE', scale: TicketScale.xlarge),
      // 行距探测：三种方式各打两行，比一比哪种真的把空隙撑开了
      ..._lineSpacingProbe(),
      TicketLine(ruler),
      const TicketLine('ruler should touch both edges'),
    ];
  }

  /// **行距探测**（打在测试页上）：三种方式各打两行，看哪种真的撑开了。
  ///
  /// 怎么看：纸上有「A1 / A2」「B1 / B2」「C1 / C2」三组，
  /// **哪一组两行之间的空隙更大，就说明这台机器认哪种指令**：
  /// - **A** = 什么都不发（打印机默认行距）—— 基准；
  /// - **B** = `ESC J 16`（打印后**直接走纸** 16 点）→ **厨师单用的就是这种**；
  /// - **C** = `ESC 3 48`（设置行距）→ 很多机器在放大字行（`GS !`）上会忽略它
  ///   （你这台就是：所以以前改行距看不出变化）。
  ///
  /// 如果 **B 组**比 A 组明显松 → 厨师单的行距旋钮
  /// （`escpos.dart` 的 `kKitchenExtraFeedDots`）就是有效的，直接调那个数。
  /// 如果 A / B / C 三组一模一样 → 这台机器不吃这两个指令，那就改用"空行"来撑
  /// （把 `kKitchenExtraFeedDots` 设 0，告诉我要用空行方案）。
  static List<TicketLine> _lineSpacingProbe() {
    final out = <TicketLine>[
      const TicketLine('--- LINE SPACING PROBE ---'),
      const TicketLine('A1 default spacing'),
      const TicketLine('A2 default spacing'),
    ];
    // B：先打这一行，再直接走纸 16 点
    for (final label in const ['B1 ESC J 16', 'B2 ESC J 16']) {
      out.add(TicketLine('',
          raw: <int>[...ascii.encode(label), 0x0A, ...feedDots(16)]));
    }
    // C：先设置行距 48 点，再打这一行
    for (final label in const ['C1 ESC 3 48', 'C2 ESC 3 48']) {
      out.add(TicketLine('',
          raw: <int>[...setLineSpacing(48), ...ascii.encode(label), 0x0A]));
    }
    out.add(const TicketLine('', raw: <int>[0x1B, 0x32])); // ESC 2：行距复位
    return out;
  }

  static String _methodLabel(Settings s, PaymentMethod? m) {
    switch (m) {
      case PaymentMethod.cash:
        return _t(s, 'payment.cash');
      case PaymentMethod.card:
        return _t(s, 'payment.card');
      case PaymentMethod.qr:
        return _t(s, 'payment.qr');
      case null:
        return '-';
    }
  }
}
