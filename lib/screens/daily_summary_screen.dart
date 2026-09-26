import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
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
  const DailySummaryScreen({super.key});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  late String _dateKey;
  final _expenseCtl = TextEditingController();
  bool _expenseLoaded = false;

  @override
  void initState() {
    super.initState();
    _dateKey = PosController.dateKey(DateTime.now());
  }

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

    final orders = pos.completedOrdersOn(_dateKey);
    final totals = computeSalesTotals(orders);
    final expense = settings.expenseFor(_dateKey);
    if (!_expenseLoaded) {
      _expenseCtl.text = expense == 0 ? '' : expense.toString();
      _expenseLoaded = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('summary.title')),
        actions: [
          // 选日期
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(_dateKey),
          ),
          // 打印日结
          IconButton(
            tooltip: L10n.t('summary.print'),
            onPressed: () => _print(totals, expense),
            icon: const Icon(Icons.print),
          ),
          const AccountMenuButton(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                              _smallRow(L10n.t('summary.date'), _dateKey),
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
                                  _dateKey,
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
                onPressed: () => _print(totals, expense),
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
    final parts = _dateKey.split('-');
    final current = DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateKey = PosController.dateKey(picked);
      _expenseLoaded = false;
    });
  }

  Future<void> _print(SalesTotals totals, double expense) async {
    final settingsCtl = context.read<SettingsController>();
    final service = context.read<ReceiptPrintService>();
    final settings = settingsCtl.settings;

    final data = SummaryData(
      storeName: settings.storeName,
      dateLabel: _dateKey,
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
