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

  /// 单子类型在小票 / 厨房单上的文字：堂食 / 外卖 / **电话外卖** / **平台外卖**。
  ///
  /// ⚠️ 这是**顾客小票**（以及界面上）的叫法；厨房单上平台外卖要打「外卖」，
  /// 见 [_kitchenTypeLabel]。
  static String _typeLabel(Settings s, OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return _t(s, 'order.dineIn');
      case OrderType.takeaway:
        return _t(s, 'order.takeaway');
      case OrderType.phonecallTakeaway:
        return _t(s, 'order.phonecallTakeaway');
      case OrderType.platformTakeaway:
        return _t(s, 'order.platformTakeaway');
    }
  }

  /// **厨房单**上单子类型的叫法 —— **平台外卖跟普通外卖一样，只打「外卖」**。
  ///
  /// 老板的要求：平台外卖（Uber / DiDi 这种）流程跟电话外卖完全一样，
  /// 但**厨师单上不用区分**（厨师只管打包，不关心单子是从哪个平台来的），
  /// 所以门牌那行和底部徽标都跟普通外卖一模一样。
  ///
  /// 想改成「厨房也看得出是平台单」：把方法体换成 `return _typeLabel(s, type);`
  /// （底部徽标另见 [_badgeKey]）。
  static String _kitchenTypeLabel(Settings s, OrderType type) =>
      _typeLabel(s,
          type == OrderType.platformTakeaway ? OrderType.takeaway : type);

  /// 厨师单**底部徽标**上那行字在 l10n 里的键（**短词**，跟 `order.*` 的长句分开）。
  static String _badgeKey(OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return 'kitchen.badgeDineIn';
      case OrderType.takeaway:
        return 'kitchen.badgeTakeaway';
      case OrderType.phonecallTakeaway:
        return 'kitchen.badgePhone';
      // 平台外卖：底部徽标**直接打「外卖」**（`LLEVAR` / `外卖`），不额外区分
      case OrderType.platformTakeaway:
        return 'kitchen.badgeTakeaway';
    }
  }

  /// 徽标上那行「**西文**」用哪门外语：
  /// - 小票语言是西语 / 英语 → 就用它；
  /// - 小票语言是**中文** → 用**西班牙语**（店在墨西哥，厨师看西文）。
  ///
  /// 想让中文票面上也永远打英语？把下面这个常量改成 `'en'`；
  /// 想干脆只打一种语言（不要"西文 + 中文"两行）？把
  /// [kitchenLines] 里的 `badgeChinese` 也改成 `''` 就行。
  static const String kBadgeFallbackLang = 'es';

  static String _badgeWesternLang(Settings s) {
    final lang = _lang(s);
    return (lang == 'es' || lang == 'en') ? lang : kBadgeFallbackLang;
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
    // **分单**：单号后面挂上「-分单1」，收银员一看就知道这是分开付钱的那一份
    final splitTag = order.isSplit
        ? '-${_t(settings, 'split.suffix')}${order.splitNo}'
        : '';

    final info = <ReceiptInfoRow>[
      ReceiptInfoRow(_t(settings, 'receipt.labelDate'),
          formatReceiptDateTime(order.createdAt, _lang(settings))),
      ReceiptInfoRow(
        _t(settings, 'receipt.labelOrder'),
        order.table.isEmpty
            ? '${order.id}$splitTag'
            : '${order.id}$splitTag  '
                '${_t(settings, 'order.table')} ${order.table}',
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
    // `raw` / `continueLine` 一起带过去（小票目前用不到，保持和厨房单一致）。
    return buildReceiptRows(data)
        .map((row) => TicketLine(row.text,
            scale: row.scale,
            bold: row.bold,
            raw: row.raw,
            continueLine: row.continueLine))
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

  /// 厨房单（下单/追单时打）：**顶部留白（别针区）+ 票号 + 时间 → 桌号/外卖名字
  /// → 菜品 → 底部「西文 + 中文」的外卖 / 堂食徽标**。
  ///
  /// 厨房单的版式跟小票一样，是"**一行带自己的字号**"（见 `receipt_layout.dart`
  /// 的 `buildKitchenRows`，那张图就是现在打出来的样子）。要点：
  /// 1. **最上面先空 1 行**（`kKitchenTopBlankRows`）—— 厨师会把单子别在杆子上，
  ///    顶上那点地方是看不见的，所以留给"票号 + 时间"这种不太要紧的信息；
  /// 2. **门牌紧跟时间**：桌号 / 外卖的名字（没名字就是系统给的号 `#3`）/
  ///    电话外卖的等待时间，全部**特大**、居中；
  /// 3. **底部是徽标**：**西文 + 中文**两行大字（`badgeWestern` / `badgeChinese`），
  ///    票面上最大的一块 —— 单子插在杆上时露出来的正是它
  ///    （以前还有 ASCII 图案，实测厨师不看，已经去掉）。西文那行见 [_badgeWesternLang]。
  ///
  /// [copyIndex] / [copyTotal]：这是第几张 / 一共几张。
  /// 默认打两张（一张厨师、一张出餐服务员），份数见 `Settings.kitchenCopies`。
  static List<TicketLine> kitchenLines(
    Order order,
    Settings settings, {
    bool isAppend = false,
    int copyIndex = 1,
    int copyTotal = 1,
    int drinksFrom = -1,
  }) {
    final badgeKey = _badgeKey(order.orderType);
    final data = KitchenData(
      table: order.table,
      orderId: order.id,
      createdAt: order.createdAt,
      lines: order.lines,
      paperWidth: settings.paperWidth,
      isAppend: isAppend,
      copyIndex: copyIndex,
      copyTotal: copyTotal,
      // **饮料排在最后**：餐品打完打一条虚线，饮料在下面（见 buildKitchenRows ④段）。
      // `-1` = 这张单没有饮料 / 调用方没算（比如测试直接构造 KitchenData）。
      drinksFrom: drinksFrom,
      // 小票编码：只给「Chico → 圆圈数字 ①」用（cp850/latin1 编不出 ①，改打 (1)）
      codec: settings.receiptCodec,
      // 电话外卖填了「等待 N 分钟」→ 厨房单上单独打一行（见 buildKitchenRows ③段）
      waitMinutes: order.waitMinutes,
      // 门牌那行要用的类型叫法（外卖打「外卖 张三」，堂食只打桌号）
      // ⚠️ 厨房单走 `_kitchenTypeLabel`：**平台外卖也打「外卖」**（不区分平台/电话）
      typeLabel: _kitchenTypeLabel(settings, order.orderType),
      // 底部徽标：**西文 + 中文**两行大字（谁都能认），见 receipt_layout.dart 的 _badgeRows
      badgeWestern: L10n.tFor(_badgeWesternLang(settings), badgeKey),
      // 中文那行是**固定要打的**：不管票面语言是西语还是英语，都出中文（店里有中国厨师）。
      // 打的时候**自己进出中文模式**（escpos.dart 的 gbkLineBytes），所以哪怕整张票
      // 设的是 `cp850` / `latin1`，这一行也不会变成 `?`。
      badgeChinese: L10n.tFor('zh', badgeKey),
      // 外卖 / 电话外卖：门牌那行打名字（没名字就打系统给的号）——见 ③段
      isTakeaway: order.isTakeaway,
      orderLabel: order.label,
      dailyNo: order.dailyNo,
      labels: KitchenLabels(
        title: _t(settings, 'kitchen.title'),
        labelTable: _t(settings, 'order.table'),
        colName: _t(settings, 'kitchen.colName'),
        colQty: _t(settings, 'kitchen.colQty'),
        // 表头最右边那一列：选项 / 特别备注打在这儿（见 buildKitchenRows ④段）
        colNote: _t(settings, 'kitchen.colNote'),
        append: _t(settings, 'kitchen.append'),
        wait: _t(settings, 'kitchen.wait'),
        minutes: _t(settings, 'kitchen.minutes'),
      ),
    );
    // `raw` / `continueLine` 必须带过去：
    // - `raw`：厨师单的"空半行"是**只走纸的原始行**（`ESC J n`，见 kKitchenBlankRowDots）；
    // - `continueLine`：菜品行 = 「数量+菜名」（加粗、不换行）紧跟「备注」（不加粗、同一行）。
    return buildKitchenRows(data)
        .map((r) => TicketLine(r.text,
            scale: r.scale,
            bold: r.bold,
            raw: r.raw,
            continueLine: r.continueLine))
        .toList();
  }

  /// 日结小票。
  ///
  /// ⚠️ **整张都是「特大」字号**（双倍宽 + 双倍高，跟厨师单的菜品一样大）——
  /// 行宽已经由 `buildSummaryLines()` 按特大下的列数（58mm = 16 列）排好了，
  /// 这里只负责把字号贴上去。
  static List<TicketLine> summaryLines(SummaryData data) =>
      buildSummaryLines(data)
          .map((l) => TicketLine(l, scale: TicketScale.xlarge))
          .toList();

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
