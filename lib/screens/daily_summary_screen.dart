import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
// 现金按币种分列时要查 `kCurrencySymbols`（币种符号表就在这个文件里）
import '../models/order.dart';
import '../services/receipt_layout.dart';
import '../services/receipt_print_service.dart';
import '../services/sales_totals.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../widgets/account_menu.dart';

/// 日结（每日汇总）：左边堂食/外卖营业额，右边日期、小计/折扣/税、
/// 现金(分币种)、刷卡、扫码、总营业额、支出（可填）、净额，
/// 右上角可以**打印这张日结**。
///
/// 汇总逻辑全在 [computeSalesTotals]（纯函数，有单元测试）：
/// 营业额按订单算，收款按**每一笔 payment** 算 —— AA 分开付的单
/// 会分别落进各自的方式/币种里，所以各方式加起来永远等于总营业额。
class DailySummaryScreen extends StatefulWidget {
  /// 打开时先看**哪一天**（`yyyy-MM-dd`）；null = 今天（并且跨零点自动跟到今天）。
  ///
  /// 从「已结单」那一页进来时会带上**正在看的那一天**：两边的"某一天"是同一套算法，
  /// 不然会出现"看着 10/3 的单子、点开日结却是今天的数字"。
  final String? initialDayKey;

  const DailySummaryScreen({super.key, this.initialDayKey});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  /// 用户**手动挑过**的日期（`yyyy-MM-dd`）；null = 跟着「今天」走。
  ///
  /// 为什么不是 `initState` 里定死一个：收银台**开着过零点**的话，
  /// 页面上的日期会一直停在昨天（你报的「今天没有结单却有一堆数字」，
  /// 这一种就是这么来的）。现在没手动挑过就每次 build 重新算"今天"。
  String? _pickedKey;

  /// 支出输入框里装的是**哪一天**的支出（换一天要重新装一遍）。
  String? _expenseFor;

  final _expenseCtl = TextEditingController();

  @override
  void dispose() {
    _expenseCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settingsCtl = context.watch<SettingsController>();
    final settings = settingsCtl.settings;
    final symbol = settings.currencySymbol;

    final dateKey = _pickedKey ??
        widget.initialDayKey ??
        PosController.dateKey(DateTime.now());
    final orders = pos.completedOrdersOn(dateKey);
    final totals = computeSalesTotals(orders);
    final expense = settings.expenseFor(dateKey);
    if (_expenseFor != dateKey) {
      _expenseCtl.text = expense == 0 ? '' : expense.toString();
      _expenseFor = dateKey;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('summary.title')),
        actions: [
          // 选日期
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(dateKey),
          ),
          // 打印日结
          IconButton(
            tooltip: L10n.t('summary.print'),
            onPressed: () => _print(totals, expense, dateKey),
            icon: const Icon(Icons.print),
          ),
          const AccountMenuButton(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 上面两块卡（堂食/外卖 + 明细）占满
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- 左：堂食 / 外卖 ----
                  Expanded(
                    child: Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(L10n.t('summary.sales'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 16),
                            _bigRow(L10n.t('summary.dineIn'), totals.dineIn,
                                symbol, const Color(0xFF1565C0)),
                            const SizedBox(height: 12),
                            _bigRow(L10n.t('summary.takeaway'),
                                totals.takeaway, symbol,
                                const Color(0xFF37474F)),
                            // 电话外卖（打电话点的）：有单才显示这一行
                            if (totals.phoneTakeaway != 0) ...[
                              const SizedBox(height: 12),
                              _bigRow(L10n.t('summary.phonecallTakeaway'),
                                  totals.phoneTakeaway, symbol,
                                  const Color(0xFF6A1B9A)),
                            ],
                            const Divider(height: 32),
                            _smallRow(L10n.t('summary.orders'),
                                '${totals.orderCount}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // ---- 右：明细 ----
                  Expanded(
                    child: Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(L10n.t('summary.title'),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 12),
                              _smallRow(L10n.t('summary.date'), dateKey),
                              const Divider(height: 24),
                              if (totals.hasAdjustments) ...[
                                _smallRow(L10n.t('receipt.labelSubtotal'),
                                    money(totals.subtotal, symbol)),
                                if (totals.discount != 0)
                                  _smallRow(
                                    L10n.t('receipt.labelDiscount'),
                                    '-${money(totals.discount, symbol)}',
                                  ),
                                if (totals.tax != 0)
                                  _smallRow(L10n.t('receipt.labelTax'),
                                      money(totals.tax, symbol)),
                                const Divider(height: 24),
                              ],
                              if (totals.cashByCurrency.isEmpty)
                                _smallRow(L10n.t('summary.cash'),
                                    money(0, symbol))
                              else
                                for (final e in totals.cashByCurrency.entries)
                                  _smallRow(
                                    e.key.isEmpty
                                        ? L10n.t('summary.cash')
                                        : '${L10n.t('summary.cash')} ${e.key}',
                                    '${kCurrencySymbols[e.key] ?? symbol}'
                                        '${e.value.toStringAsFixed(2)}',
                                  ),
                              _smallRow(L10n.t('summary.card'),
                                  money(totals.card, symbol)),
                              if (totals.qr != 0)
                                _smallRow(L10n.t('summary.qr'),
                                    money(totals.qr, symbol)),
                              const Divider(height: 24),
                              _smallRow(L10n.t('summary.total'),
                                  money(totals.total, symbol),
                                  bold: true),
                              const SizedBox(height: 12),
                              // 支出：留一个空让用户填
                              TextField(
                                controller: _expenseCtl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  labelText: L10n.t('summary.expense'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  prefixText: symbol,
                                ),
                                onChanged: (v) => settingsCtl.setDailyExpense(
                                  dateKey,
                                  double.tryParse(
                                          v.trim().replaceAll(',', '.')) ??
                                      0,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _smallRow(
                                L10n.t('summary.net'),
                                money(totals.total - expense, symbol),
                                bold: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _print(totals, expense, dateKey),
                icon: const Icon(Icons.print),
                label: Text(L10n.t('summary.print')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigRow(String label, double amount, String symbol, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(money(amount, symbol),
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700, color: color)),
        ],
      );

  Widget _smallRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: bold ? 15 : 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 17 : 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ],
        ),
      );

  Future<void> _pickDate() async {
    // 选择器打开时定位在**现在看着的那一天**
    final current = _pickedKey ??
        widget.initialDayKey ??
        PosController.dateKey(DateTime.now());
    final parts = current.split('-');
    final initial = DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _pickedKey = PosController.dateKey(picked));
  }

  Future<void> _print(
    SalesTotals totals,
    double expense,
    String dateKey,
  ) async {
    final settingsCtl = context.read<SettingsController>();
    final service = context.read<ReceiptPrintService>();
    final settings = settingsCtl.settings;

    final data = SummaryData(
      storeName: settings.storeName,
      dateLabel: dateKey,
      paperWidth: settings.paperWidth,
      currency: settings.currencySymbol,
      dineInTotal: totals.dineIn,
      takeawayTotal: totals.takeaway,
      phoneTakeawayTotal: totals.phoneTakeaway,
      cashByCurrency: totals.cashByCurrency,
      cardTotal: totals.card,
      qrTotal: totals.qr,
      subtotalTotal: totals.subtotal,
      discountTotal: totals.discount,
      taxTotal: totals.tax,
      total: totals.total,
      expense: expense,
      orderCount: totals.orderCount,
      labels: SummaryLabels(
        title: L10n.t('summary.title'),
        date: L10n.t('summary.date'),
        dineIn: L10n.t('summary.dineIn'),
        takeaway: L10n.t('summary.takeaway'),
        phoneTakeaway: L10n.t('summary.phonecallTakeaway'),
        cash: L10n.t('summary.cash'),
        card: L10n.t('summary.card'),
        qr: L10n.t('summary.qr'),
        subtotal: L10n.t('receipt.labelSubtotal'),
        discount: L10n.t('receipt.labelDiscount'),
        tax: L10n.t('receipt.labelTax'),
        total: L10n.t('summary.total'),
        expense: L10n.t('summary.expense'),
        net: L10n.t('summary.net'),
        orders: L10n.t('summary.orders'),
      ),
    );

    final err = await service.printSummary(data, settings);
    if (!mounted) return;
    // 成功不弹提示（你说的那种下方横幅已取消），失败才提示
    if (err != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('${L10n.t('dialog.print.failed')} $err'),
        ));
    }
  }
}
