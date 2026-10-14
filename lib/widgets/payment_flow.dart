import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../services/receipt_print_service.dart';
import '../state/auth_controller.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/pricing.dart';
import 'bank_card_anim.dart';
import 'takeaway_name_dialog.dart';

/// 收款框点「确认收款」后的结果。
///
/// 现金会带上币种、汇率、实收、找零（**都用客人付的那个币种计**）；
/// 刷卡只带方式。
class CheckoutResult {
  final DiscountType discountType;
  final double discountValue;

  final PaymentMethod method;

  /// 客人付的币种（MXN / USD / RMB）。等于本位币时汇率是 1。
  final String currencyCode;

  /// 1 个 [currencyCode] = 多少本位币。
  final double exchangeRate;

  /// 现金：实收（按 [currencyCode] 计）。刷卡为 null。
  final double? received;

  /// 现金：找零（按 [currencyCode] 计）。刷卡为 null。
  final double? change;

  const CheckoutResult({
    required this.discountType,
    required this.discountValue,
    required this.method,
    this.currencyCode = '',
    this.exchangeRate = 0,
    this.received,
    this.change,
  });
}

/// 结账窗口（**屏幕中间，左右两栏，一个页面搞定**）：
///
/// **左边 30%** = 这张单的菜（明细）+ **底部的金额明细（小计 / 折扣 / 税 / 合计）**；
/// **右边 70%** = 全部操作，从上到下：
/// **应收（跟着收款币种变的大字）→ 折扣 → 收款币种 → 支付方式 →
/// 现金（实收 + 右边一排快捷金额 + 大字找零）/ 刷卡（银行卡动画）**。
///
/// 右下角两个按钮：**`打印单子`**（打完留在本界面，可以再打，标一行「已打印 HH:MM」）
/// 和 **`确认收款`**（点它落账、关窗）。**没有「取消」按钮**：退出点标题栏的 ✕。
///
/// 其它取舍：
/// - **没有 AA 分开付**：一单一次收清，界面和账都简单；
/// - **应收直接按收款币种显示**（`应收 $40.00 USD`），不再另写一行换算；
/// - 币种按钮只有「币种码 + 汇率」，没设汇率的那个点不动；
/// - 折扣在窗口里给（它会计进左边的小计/合计，也会打进纸里）；
/// - 没有扫码。
///
/// [printBill] 由调用方（`settleOrderFlow`）提供：把当前这张单打成「单子」，
/// 返回 null 表示成功。打不出来会弹「重试 / 跳过」。
Future<CheckoutResult?> showCheckoutDialog(
  BuildContext context, {
  required Order order,
  required Settings settings,
  required String cashier,
  required Future<PrintError?> Function(Order) printBill,
}) {
  return showDialog<CheckoutResult>(
    context: context,
    builder: (_) => _CheckoutDialog(
      order: order,
      settings: settings,
      cashier: cashier,
      printBill: printBill,
    ),
  );
}

class _CheckoutDialog extends StatefulWidget {
  final Order order;
  final Settings settings;
  final String cashier;

  /// 打「单子」：结账窗口里点「打印单子 / 再打一张」时调用（明细+合计）。
  final Future<PrintError?> Function(Order) printBill;

  const _CheckoutDialog({
    required this.order,
    required this.settings,
    required this.cashier,
    required this.printBill,
  });

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  /// 正在打单（防止连点两次打出两张）。
  bool _printing = false;

  /// 本界面上**已经成功打过单子**的时刻（null = 还没打过）。
  ///
  /// 只用来给收银员一个「这单已经出过纸了」的提示（按钮变「再打一张」+
  /// 右下角一行「已打印 HH:MM」），**不参与任何判断** ——
  /// 没打过也照样能点「确认」去收款。
  DateTime? _printedAt;

  /// 本帧要显示的那张单。
  ///
  /// **每帧从 PosController 取最新的**：窗口里删过菜之后，打开窗口时传进来的
  /// 那个 `order` 就是旧对象了，金额必须按新的算（见 [build] 第一行）。
  late Order _order = widget.order;

  late DiscountType _discountType = widget.order.discountType;
  late double _discountValue = widget.order.discountValue;
  late final TextEditingController _discountCtl = TextEditingController(
    text: _discountValue == 0 ? '' : _fmt(_discountValue),
  );

  PaymentMethod _method = PaymentMethod.cash;

  /// 客人付的币种（默认本位币）。
  late String _currency = widget.settings.baseCurrency;

  final _receivedCtl = TextEditingController();
  bool _receivedTouched = false;

  /// 收款框内容可以滚动；切到「现金/刷卡」时自动滚到底部，
  /// 让收银员**不用手滑**就能看到实收框 / 找零 / 银行卡动画。
  final _scrollCtl = ScrollController();

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    // 默认按「正好收」预填实收
    _receivedCtl.text = _fmt(_dueForeign);
  }

  @override
  void dispose() {
    _discountCtl.dispose();
    _receivedCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  /// 换支付方式：顺便把视图滑到底（看实收/找零/银行卡）。
  void _setMethod(PaymentMethod m) {
    setState(() => _method = m);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      _scrollCtl.animateTo(
        _scrollCtl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// 打完折之后的金额明细（本位币）。
  ///
  /// 用 [_order]（**每帧取最新的那张单**）而不是 `widget.order`：
  /// 窗口里删过菜之后，金额必须按删完的算。
  PriceBreakdown get _price => PriceBreakdown.of(
        subtotal: _order.subtotal,
        discountType: _discountType,
        discountValue: _discountValue,
        taxRate: _order.taxRate,
        taxIncluded: _order.taxIncluded,
      );

  /// 选中币种的汇率（本位币 = 1；没设过 = 0）。
  double get _rate => widget.settings.rateFor(_currency);

  /// 该币种的应收。
  double get _dueForeign => toForeign(_price.total, _rate);

  String get _symbol => _currency == widget.settings.baseCurrency
      ? widget.settings.currencySymbol
      : (kCurrencySymbols[_currency] ?? widget.settings.currencySymbol);

  double? get _received => _parse(_receivedCtl.text);

  /// 找零（按该币种算）；实收没填就当作正好。
  double get _change => round2((_received ?? _dueForeign) - _dueForeign);

  /// 实收的**快捷金额**：第一个永远是「正好」，后面两个是**邻近的整数**。
  ///
  /// 例：应收 240 → `正好 240 / 250 / 300`；应收 550 → `正好 550 / 600 / 1000`。
  /// 规则本身在 `utils/pricing.dart` 的 `quickReceivedAmounts()`（有单测）。
  List<double> get _quickReceived => quickReceivedAmounts(_dueForeign);

  /// 点快捷金额：填进实收框（并标记「客人付的钱已经改过」，不再跟着折扣联动）。
  void _applyReceived(double v) {
    setState(() {
      _receivedTouched = true;
      _receivedCtl.text = _fmt(v);
    });
  }

  static double? _parse(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    return (v == null || v < 0) ? null : v;
  }

  void _onDiscountChanged(String raw) {
    final v = _parse(raw) ?? 0;
    setState(() {
      _discountValue = v;
      if (!_receivedTouched) _receivedCtl.text = _fmt(_dueForeign);
    });
  }

  void _setDiscountType(DiscountType t) {
    setState(() {
      _discountType = t;
      if (t == DiscountType.none) {
        _discountValue = 0;
        _discountCtl.clear();
      } else if (_discountValue == 0) {
        _discountCtl.clear();
      }
      if (!_receivedTouched) _receivedCtl.text = _fmt(_dueForeign);
    });
  }

  void _applyQuickDiscount(double pct) {
    _discountCtl.text = _fmt(pct);
    _onDiscountChanged(_discountCtl.text);
  }

  void _pickCurrency(String code) {
    setState(() {
      _currency = code;
      if (!_receivedTouched) _receivedCtl.text = _fmt(_dueForeign);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 每帧取最新的这张单：窗口里删过菜之后，widget.order 就是旧对象了
    _order = context.watch<PosController>().findOrder(widget.order.id) ??
        widget.order;

    final baseSymbol = widget.settings.currencySymbol;
    final isCash = _method == PaymentMethod.cash;
    final price = _price;
    final change = _change;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleBar(),
            const Divider(height: 1),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ------- 左边 30%：单子明细 + **底部的金额明细（小计/合计）** -------
                  Expanded(flex: 3, child: _linesPane(baseSymbol, price)),
                  const VerticalDivider(width: 1),
                  // ------- 右边 70%：应收 + 折扣 + 收款币种 + 支付方式 + 收款 -------
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollCtl,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ---------------- 应收（跟着收款币种变）----------------
                                _dueBig(),
                                const SizedBox(height: 12),

                                // ---------------- 折扣 ----------------
                                _label(L10n.t('checkout.discount')),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _chip(
                                      L10n.t('checkout.discount.none'),
                                      _discountType == DiscountType.none,
                                      () => _setDiscountType(DiscountType.none),
                                    ),
                                    _chip(
                                      L10n.t('checkout.discount.percent'),
                                      _discountType == DiscountType.percent,
                                      () => _setDiscountType(DiscountType.percent),
                                    ),
                                    _chip(
                                      L10n.t('checkout.discount.amount'),
                                      _discountType == DiscountType.amount,
                                      () => _setDiscountType(DiscountType.amount),
                                    ),
                                  ],
                                ),
                                if (_discountType != DiscountType.none) ...[
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _discountCtl,
                                    keyboardType: const TextInputType
                                        .numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText:
                                          _discountType == DiscountType.percent
                                              ? L10n.t(
                                                  'checkout.discount.percentHint')
                                              : L10n.t(
                                                  'checkout.discount.amountHint'),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      prefixText:
                                          _discountType == DiscountType.percent
                                              ? null
                                              : baseSymbol,
                                      suffixText:
                                          _discountType == DiscountType.percent
                                              ? '%'
                                              : null,
                                    ),
                                    onChanged: _onDiscountChanged,
                                  ),
                                  if (_discountType == DiscountType.percent) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final pct in const [
                                          5.0,
                                          10.0,
                                          15.0,
                                          20.0
                                        ])
                                          OutlinedButton(
                                            onPressed: () =>
                                                _applyQuickDiscount(pct),
                                            child: Text(
                                                '${pct.toStringAsFixed(0)}%'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],

                                // ---------------- 收款币种（只有币种码 + 汇率）------------
                                const SizedBox(height: 14),
                                _label(L10n.t('checkout.currency')),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final code in kCashCurrencies)
                                      _currencyChip(code),
                                  ],
                                ),

                                // ---------------- 支付方式 ----------------
                                const SizedBox(height: 14),
                                _label(L10n.t('checkout.payMethod')),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _chip(L10n.t('payment.cash'), isCash,
                                        () => _setMethod(PaymentMethod.cash)),
                                    _chip(
                                        L10n.t('payment.card'),
                                        _method == PaymentMethod.card,
                                        () => _setMethod(PaymentMethod.card)),
                                  ],
                                ),

                                // ---------------- 现金：实收（右边跟快捷金额）+ 大字找零 ----
                                if (isCash) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _receivedCtl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            labelText:
                                                '${L10n.t('pay.received')} ($_currency)',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            prefixText: '$_symbol ',
                                          ),
                                          onChanged: (_) => setState(
                                              () => _receivedTouched = true),
                                        ),
                                      ),
                                      // 快捷金额（正好 + 三个取整档）**就在实收框右边**
                                      for (var i = 0;
                                          i < _quickReceived.length;
                                          i++) ...[
                                        const SizedBox(width: 6),
                                        ActionChip(
                                          onPressed: () =>
                                              _applyReceived(_quickReceived[i]),
                                          label: Text(
                                            i == 0
                                                ? L10n.t('pay.exact')
                                                : _fmt(_quickReceived[i]),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: i == 0
                                                  ? const Color(0xFF1FA85A)
                                                  : const Color(0xFF232829),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // 找零：**大字**（要一眼看清，找错钱就麻烦了）
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: change < 0
                                          ? const Color(0xFFFFEBEE)
                                          : const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          change < 0
                                              ? L10n.t('pay.short')
                                              : L10n.t('pay.change'),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: change < 0
                                                ? Colors.red.shade700
                                                : const Color(0xFF2E7D32),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          money(change.abs(), _symbol),
                                          style: TextStyle(
                                            fontSize: 44,
                                            height: 1.1,
                                            fontWeight: FontWeight.w800,
                                            color: change < 0
                                                ? Colors.red.shade700
                                                : const Color(0xFF1FA85A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // ---------------- 刷卡：银行卡动画 ----------------
                                if (!isCash) ...[
                                  const SizedBox(height: 10),
                                  Center(
                                    child: BankCardAnim(
                                      width: 220,
                                      hint: L10n.t('checkout.cardHint'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // 右下角：`打印单子` + `确认收款`（一个页面搞定，不用再翻页）
                        const Divider(height: 1),
                        _actionRow(context, isCash: isCash, change: change),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 标题栏：结账 + 桌号 / 外卖（**外卖把名字 / 号也写上，电话外卖再加等待时间**）
  /// + 收银员 + 关闭。
  ///
  /// 为什么外卖要写名字：外卖没有桌号，收银员核对的就是"名字 / 号"；
  /// 电话外卖还带着客人说好的等待时间（跟厨房单上打的一致）。
  Widget _titleBar() {
    final tag = _order.takeawayTag; // `名字 #号` / `名字` / `#号` / ''（老数据没有）
    final wait = (_order.isPhoneTakeaway && _order.waitMinutes > 0)
        ? '   ·   ${L10n.t('kitchen.wait')} ${_order.waitMinutes} '
            '${L10n.t('kitchen.minutes')}'
        : '';
    final typeText = _order.isPhoneTakeaway
        ? '${L10n.t('order.phonecallTakeaway')}'
            '${tag.isEmpty ? '' : ' $tag'}$wait'
        : _order.isTakeaway
            ? '${L10n.t('order.takeaway')}${tag.isEmpty ? '' : ' $tag'}$wait'
            : (_order.table.isEmpty
                ? ''
                : '${L10n.t('order.table')} ${_order.table}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Row(
        children: [
          Text(
            L10n.t('checkout.title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (typeText.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                typeText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (widget.cashier.isNotEmpty)
            Text(
              '${L10n.t('pay.cashier')}: ${widget.cashier}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: L10n.t('common.cancel'),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  /// 应收大字：**按选中的收款币种显示** —— `应收 $660.00 MXN` / `应收 $40.00 USD`。
  ///
  /// 大小和颜色跟以前一样；换币种时**这个数字直接跟着变**
  /// （以前是"本位币应收 + 下面一行换算"，现在只有这一行）。
  Widget _dueBig() => Text(
        '${L10n.t('pay.due')}  ${money(_dueForeign, _symbol)} $_currency',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1FA85A),
        ),
      );

  /// 左边 30%：这张单的明细（**只显示**）+ **底部的金额明细（小计/折扣/税/合计）**。
  ///
  /// 金额明细放在这里（而不是右边）是为了把右边的空间让给"折扣 / 收款币种 /
  /// 支付方式 / 实收找零"这些**要动手的地方**；它照样跟着右边的操作实时变。
  ///
  /// 要删菜 / 改份数 / 改备注，都去**点单界面**的购物车里改（你说的：所有改动都在点单界面完成）。
  Widget _linesPane(String baseSymbol, PriceBreakdown price) {
    return Container(
      color: const Color(0xFFF7F9F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              '${L10n.t('checkout.items')}  '
              '${_order.itemCount}${L10n.t('cart.items')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: _order.lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _lineTile(i, baseSymbol),
            ),
          ),
          // ---- 金额明细（小计 / 折扣 / 税 / 合计）**在清单底部** ----
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: _breakdown(price, baseSymbol),
          ),
        ],
      ),
    );
  }

  /// 明细里的一道菜（只读）：菜名 + 选项/备注 + 数量×单价 + 金额。
  Widget _lineTile(int index, String symbol) {
    final l = _order.lines[index];
    final detail = <String>[
      '${l.quantity} × ${money(l.unitPrice, symbol)}'
          '${l.unit.trim().isEmpty ? '' : ' / ${l.unit.trim()}'}',
      if (l.options.isNotEmpty) l.options.join(' / '),
      if (l.note.trim().isNotEmpty) l.note.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 结账窗口是**给收银员看的**：跟点单页一样显示昵称
                  // （纸上的顾客小票用的是全名，见 `receipt_layout.dart`）
                  l.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            money(l.subtotal, symbol),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// 右下角的按钮行（**一个页面，就这两个按钮**）：
  ///
  /// - 左：**`打印单子`**（打完留在本界面，可以再打；打成功了标一行「已打印 HH:MM」）；
  /// - 右：**`确认收款`**（现金还差钱时是灰的）—— 点它就落账、关窗。
  ///
  /// **没有「取消」按钮**：要退出就点标题栏右上角的 ✕。
  Widget _actionRow(
    BuildContext context, {
    required bool isCash,
    required double change,
  }) {
    final printed = _printedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 打过纸了：标一行时间，收银员回来一眼就知道不用再打（**纯粹是提示**）
          if (printed != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF1FA85A)),
                  const SizedBox(width: 6),
                  Text(
                    '${L10n.t('checkout.printed')} ${timeHm(printed)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printing ? null : () => _printBill(context),
                  icon: _printing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(printed == null
                      ? L10n.t('checkout.printBill')
                      : L10n.t('checkout.printAgain')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  // 现金还差钱才禁用；**刷卡**时不看实收框（免得先输过现金再切刷卡就点不动了）
                  onPressed: (isCash && change < 0)
                      ? null
                      : () => _finish(context, isCash, change),
                  child: Text(isCash
                      ? L10n.t('checkout.collect')
                      : L10n.t('checkout.cardDone')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 要打出去的那张单：**把屏幕上刚设的折扣临时贴上去**。
  ///
  /// 折扣这时还没写进订单（要等收款成功才落账），所以临时造一张「带折扣的单」去打印，
  /// 这样纸上的合计 = 屏幕上显示的合计 = 最后记账的金额。
  Order _billToPrint() => _order.copyWith(
        discountType: _discountType,
        discountValue: _discountValue,
        total: _price.total,
      );

  /// ① 的「打印单子 / 再打一张」：打纸，**留在本界面**。
  ///
  /// 这是这次改动的重点：打完**不切界面、也不锁任何东西** ——
  /// 收银员打完单子可以先去忙别的，回来直接点「确认」进收款，不用再打一遍。
  /// 打成功了标一个「已打印 HH:MM」（只是提示，不参与判断）。
  Future<void> _printBill(BuildContext context) async {
    if (_printing) return;
    setState(() => _printing = true);

    final bill = _billToPrint();
    final err = await widget.printBill(bill);
    // 两个都查一下：mounted 是 State 的（下面要 setState），context.mounted 是因为
    // 后面还要拿这个 context 弹窗 —— 分析器只认「跟用到的 context 对得上」的那个检查。
    if (!mounted || !context.mounted) return;
    setState(() {
      _printing = false;
      if (err == null) _printedAt = DateTime.now();
    });

    if (err != null) {
      // 打不出来：让收银员「重试打印」或「跳过」（跳过也**留在本界面**，可以点「确认」收款）
      await showPrintFailureSheet(context, err, () async {
        final retryErr = await widget.printBill(bill);
        // 重试成功也算打过（弹窗内部自己关掉了，结果不回传给这里）
        if (retryErr == null && mounted) {
          setState(() => _printedAt = DateTime.now());
        }
        return retryErr;
      });
    }
  }

  /// 收款完成 —— 把结果交回给 `settleOrderFlow` 落账，窗口关闭。
  /// （「单子」想打就点左边那个按钮打过了，收款这里**不打纸**。）
  void _finish(BuildContext context, bool isCash, double change) {
    Navigator.pop(
      context,
      CheckoutResult(
        discountType: _discountType,
        discountValue: _discountValue,
        method: _method,
        currencyCode: _currency,
        // 本位币传 0：表示「不需要换算」，外币才传真实汇率
        exchangeRate:
            _currency == widget.settings.baseCurrency ? 0 : _rate,
        received: isCash ? (_received ?? _dueForeign) : null,
        change: isCash ? change : null,
      ),
    );
  }

  /// 小计 / 折扣 / 税 / 合计（显示在**左边清单的底部**）。
  ///
  /// 折扣那一行的说明文字用**窗口里当前选的折扣**（`_discountType/_discountValue`），
  /// 不能读订单上存的那个：订单要等收款成功才落账，这会儿它还是"没折扣"。
  Widget _breakdown(PriceBreakdown price, String symbol) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _row(L10n.t('receipt.labelSubtotal'), money(price.subtotal, symbol)),
          if (price.discount != 0)
            _row(
              '${L10n.t('receipt.labelDiscount')}${_discountText(symbol)}',
              '-${money(price.discount, symbol)}',
              color: const Color(0xFFEF6C00),
            ),
          if (price.tax != 0)
            _row(
              '${L10n.t('receipt.labelTax')}'
              '${_order.taxRate == 0 ? '' : ' ${_fmt(_order.taxRate)}%'}'
              '${_order.taxIncluded ? ' (${L10n.t('tax.included')})' : ''}',
              money(price.tax, symbol),
            ),
          const Divider(height: 12),
          _row(L10n.t('receipt.labelTotal'), money(price.total, symbol),
              bold: true),
        ],
      ),
    );
  }

  /// 折扣的括号说明：` 10%` / ` -¥20.00`；没折扣返回空串。
  String _discountText(String symbol) {
    switch (_discountType) {
      case DiscountType.none:
        return '';
      case DiscountType.percent:
        return ' ${_fmt(_discountValue)}%';
      case DiscountType.amount:
        return ' -${money(_discountValue, symbol)}';
    }
  }

  /// 一个币种的按钮：**只有币种码 + 汇率**，别的什么都不显示。
  ///
  /// - 本位币 → `MXN  本位币`；
  /// - 设过汇率 → `USD  16.5`（1 个 USD = 16.5 本位币）；
  /// - 没设汇率 → `RMB  未设汇率`（这一项点不动）。
  ///
  /// **换算后的应收不在这里** —— 上面那行「应收」大字会跟着切换
  /// （`应收 $40.00 USD`），这样币种按钮能瘦下来，一眼看的就是那一个数字。
  Widget _currencyChip(String code) {
    final rate = widget.settings.rateFor(code);
    final usable = rate > 0;
    final selected = _currency == code;
    final isBase = code == widget.settings.baseCurrency;
    final sub = isBase
        ? L10n.t('checkout.base')
        : (usable ? _fmt(rate) : L10n.t('checkout.noRate'));

    return ChoiceChip(
      selected: selected,
      onSelected: usable ? (_) => _pickCurrency(code) : null,
      showCheckmark: false,
      selectedColor: const Color(0xFF1FA85A),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : (usable ? const Color(0xFF232829) : Colors.grey),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            sub,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 17 : 15,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: bold ? 19 : 15,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        label: Text(label),
        showCheckmark: false,
        selectedColor: const Color(0xFF1FA85A),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF232829),
          fontWeight: FontWeight.w600,
        ),
      );
}

/// 购物车下面**左边那个「保存」**：把本次新增的菜记到这张桌的单上，**不打厨房单**。
///
/// 用在「不用惊动厨房」的菜上：酒水、饮料、先垫着不下厨的菜。
/// 记完之后菜会出现在购物车上面的「已在单上」区，标成**橙色「未下厨」**，
/// 下次点「厨房」时会跟别的没下厨的菜一起打给厨房。
Future<void> saveOrderFlow(BuildContext context) =>
    _submitOrder(context, toKitchen: false, askName: true);

/// 购物车下面**中间那个「厨房」**：把本次新增的菜记到单上，然后**打厨房单**。
///
/// 厨房单打的是这张单上**所有还没下厨的行**（包括之前「保存」过的），
/// 所以厨房不会漏菜；打成功了才把这些行标成「已下厨」（失败可以再点一次重打）。
Future<void> kitchenOrderFlow(BuildContext context) =>
    _submitOrder(context, toKitchen: true);

/// 购物车下面**右边那个「结账」**：**先记单**（跟「保存」一样），
/// 然后**直接打开这张单的结账窗口**（就是订单页那个「结账」）。
///
/// 为什么要它：客人到店点外卖、点完当场就要付钱 —— 不用再绕到「订单」页去找那张单。
/// 结完账这张单就变成「已结单」（要不要打小票在结账窗口里自己决定）。
///
/// 两个细节：
/// - **不问外卖名字**（跟「保存」不同）：客人正等着付钱，别在这时候弹起名框；
/// - **没起名字的外卖单**既没桌号也没名字，`openOrderForSelectedTable()` 是找不到它的
///   （那是故意的设计），所以兜底用"刚刚动过的那一张"（`lastTouchedOrder`）——
///   这样"点完厨房再点结账"也能结到正确的那张单。
Future<void> checkoutOrderFlow(BuildContext context) async {
  final pos = context.read<PosController>();
  // 购物车里有菜 → 先记到单上（这一步跟「保存」完全一样，只是不问名字）
  final saved = await _submitOrder(context, toKitchen: false, askName: false);
  if (!context.mounted) return;
  // 购物车本来就是空的（比如刚点过「厨房」）→ 结"当前这张还没结的单"
  final order =
      saved ?? pos.openOrderForSelectedTable() ?? pos.lastTouchedOrder;
  if (order == null) return; // 没东西可结
  await settleOrderFlow(context, order);
}

/// 「保存」「厨房」「结账」共用的流程：**先记单，再（可选）打厨房单**。
///
/// 目标是**当前选中的桌**：那桌已经有进行中的单就自动**并进那张单**；
/// 外卖每单独立（当前行为，不自动并入 —— 见 `openOrderForSelectedTable`）。
///
/// 返回**刚记下的那张单**（购物车空、或者没东西可记时返回 null）——
/// 「结账」那个按钮要用它。
///
/// [askName] 只在「保存」时为 true：外卖单存下来之后顺口问一句"要不要起个名字"
/// （起名 = 存进下拉列表，之后能选回来接着改）；「结账」时**不问**，直接去收款。
Future<Order?> _submitOrder(
  BuildContext context, {
  required bool toKitchen,
  bool askName = false,
}) async {
  final pos = context.read<PosController>();
  final settingsCtl = context.read<SettingsController>();
  final service = context.read<ReceiptPrintService>();
  final cashier = context.read<AuthController>().currentName;
  final settings = settingsCtl.settings;

  if (!pos.hasTableSelected) return null;

  // 这张单要打/要记的（下面两个分支都会赋值）
  final Order order;

  if (!pos.cartEmpty) {
    // ---- 1) 购物车里有新菜：先记到这张桌的单上（没有单就开一张）----
    // 先记单再打印：打印失败也不会丢单（跟以前一样）
    final open = pos.openOrderForSelectedTable();
    final saved = open != null
        ? pos.appendToOrder(open.id)
        : pos.placeOrder(
            taxRate: settings.taxRate,
            taxIncluded: settings.taxIncluded,
            cashier: cashier,
          );
    if (saved == null) return null;
    // 记下来"刚动过的是哪张单"：「结账」按钮靠它兜底（尤其是没名字的外卖单）
    pos.markTouchedOrder(saved.id);
    // 「保存」到此为止：只记单，不打印。
    //
    // 外卖单顺手问一句"要不要起个名字"：**起名 = 把这张外卖单存进下拉列表**，
    // 之后随时能选回来接着加菜/改单（结账后自动从列表消失）。
    // 点「不用名字」也没关系 —— 那就是一张点完厨房直接结账的普通外卖单。
    if (!toKitchen) {
      if (askName &&
          saved.isTakeaway &&
          saved.label.trim().isEmpty &&
          context.mounted) {
        // 外卖 / 电话外卖：「保存这张外卖单」= 起名（可不填）+ 电话外卖的等待时间
        final r = await showTakeawayNameDialog(context, saved);
        if (r != null) {
          pos.setOrderLabel(saved.id, r.label, waitMinutes: r.waitMinutes);
        }
      }
      return saved;
    }
    order = saved;
  } else {
    // ---- 1') 购物车是空的 ----
    // 「保存」没东西可存；「厨房」仍然要能打：把这张单上**还没下厨的菜**补打给厨房
    // （比如先点了「保存」，或者上一次厨房单没打成功、失败被跳过）
    if (!toKitchen) return null;
    final open = pos.openOrderForSelectedTable();
    if (open == null) return null; // 这桌没有进行中的单 → 没东西可打
    pos.markTouchedOrder(open.id);
    order = open;
  }

  // ---- 2) 厨房单：这张单上所有还没下厨的菜 ----
  final pending = pos.unsentLines(order.id);
  if (pending.isEmpty) return order;

  final ticket = Order(
    id: order.id,
    createdAt: order.createdAt,
    lines: pending,
    total: 0,
    table: order.table,
    orderType: order.orderType,
    // 外卖那三样要**跟着票走**，否则厨房单顶部打不出「名字 / 号 / 等待时间」
    // （见 `receipt_layout.dart` 的 buildKitchenRows ①b / ②b）
    label: order.label,
    dailyNo: order.dailyNo,
    waitMinutes: order.waitMinutes,
    status: OrderStatus.inProgress,
  );
  // 这张单之前已经下过厨房 → 票上标「（追加）」
  final isAppend = order.lines.any((l) => l.sentToKitchen);

  Future<PrintError?> printTicket() =>
      service.printKitchenTicket(ticket, settings, isAppend: isAppend);

  final err = await printTicket();
  if (!context.mounted) return order;

  if (err == null) {
    // 打成功了才算「下过厨房」
    pos.markOrderSent(order.id);
    return order;
  }

  // 打不出来：让收银员「重试打印」或「跳过」；**重试成功才标已下厨**
  await showPrintFailureSheet(context, err, () async {
    final retryErr = await printTicket();
    if (retryErr == null) pos.markOrderSent(order.id);
    return retryErr;
  });
  // 打印失败 / 被跳过也把这张单交回去 —— 「结账」照样得能结
  return order;
}

/// 结账流程：一个结账窗口（明细 + 折扣 + 收款都在一页）→ 记成已结单。
///
/// **打纸跟收款解开**：想打就点「打印单子」（明细 + 合计，含刚设的折扣），
/// 打完留在原界面（可以再打、也可以走开一会儿）；点「确认收款」才落账、关窗，
/// **点确认的时候不再出纸**。打印失败的处理（重试 / 跳过）在窗口内部（见 `_printBill`）。
Future<void> settleOrderFlow(BuildContext context, Order order) async {
  final pos = context.read<PosController>();
  final settingsCtl = context.read<SettingsController>();
  final service = context.read<ReceiptPrintService>();
  final cashier = context.read<AuthController>().currentName;
  final settings = settingsCtl.settings;

  final result = await showCheckoutDialog(
    context,
    order: order,
    settings: settings,
    cashier: cashier,
    // 「单子」= 这张进行中的单（明细 + 合计，还没有支付信息）
    printBill: (o) => service.printReceipt(o, settings),
  );
  if (result == null || !context.mounted) return;

  // 记账：金额按订单**当前**的行算（窗口里可能刚删过菜），折扣用窗口里选的
  pos.closeOrder(
    order.id,
    result.method,
    discountType: result.discountType,
    discountValue: result.discountValue,
    currencyCode: result.currencyCode,
    exchangeRate: result.exchangeRate,
    receivedAmount: result.received,
    changeAmount: result.change,
    cashier: cashier,
  );
}

/// 打印失败弹窗：重试 / 跳过并继续。
Future<void> showPrintFailureSheet(
  BuildContext context,
  PrintError error,
  Future<PrintError?> Function() retry,
) async {
  bool retrying = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(L10n.t('dialog.print.failed')),
            content: Text(
              _errorMessage(error),
              style: const TextStyle(color: Colors.redAccent),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(L10n.t('dialog.print.skip')),
              ),
              FilledButton(
                onPressed: () async {
                  if (retrying) return;
                  setState(() => retrying = true);
                  final res = await retry();
                  if (!dialogContext.mounted) return;
                  if (res == null) {
                    // 重试成功：直接关掉这个框就行，不再弹「打印成功」
                    Navigator.pop(dialogContext);
                  } else {
                    setState(() => retrying = false);
                  }
                },
                child: Text(retrying
                    ? L10n.t('settings.scanning')
                    : L10n.t('dialog.print.retry')),
              ),
            ],
          );
        },
      );
    },
  );
}

String _errorMessage(PrintError error) {
  if (L10n.isChinese) {
    switch (error) {
      case PrintError.noPrinter:
        return '未选择打印机，请到「设置」里连接。';
      case PrintError.notConnected:
        return '打印机未连接，请检查连接。';
      case PrintError.ioError:
        return '写入打印机失败，请确认打印机已开机并有纸。';
      case PrintError.unsupported:
        return '当前平台暂不支持该打印机。';
    }
  } else {
    switch (error) {
      case PrintError.noPrinter:
        return 'No printer selected. Connect one in Settings.';
      case PrintError.notConnected:
        return 'Printer is not connected.';
      case PrintError.ioError:
        return 'Failed to write to printer. Check it is on and has paper.';
      case PrintError.unsupported:
        return 'This printer is not supported on this platform yet.';
    }
  }
}
