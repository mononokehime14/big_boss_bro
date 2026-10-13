import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../services/receipt_print_service.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart'; // money() / timeShort()
import '../utils/order_label.dart'; // 桌号·外卖标签、支付方式
import '../utils/order_sort.dart'; // closedOrCreatedAt()：结账时间（老数据用开单时间）
import 'payment_flow.dart'; // showPrintFailureSheet()：打印失败的重试 / 跳过

/// 「已结单」的单子**点一下**就开它：**看明细 + 补打小票**，就这两件事。
///
/// 为什么**没有「结账」**：这张单的钱早就收过了（它已经是"已结单"），
/// 不需要再收一次；实际用得上的只有——
/// - 客人回来问"我刚点了什么 / 多少钱"→ 看一眼明细；
/// - **补打小票**（客人要一张、或者当初没打出来 / 打糊了）。
///
/// 打的是**顾客小票**（跟结账时那张同一个排版函数 `TicketBuilder.receiptLines`）：
/// 结过账的单子里已经有支付方式 / 实收 / 找零，所以补打出来的票面是完整的。
Future<void> showClosedOrderDetail(BuildContext context, Order order) async {
  final symbol = context.read<SettingsController>().settings.currencySymbol;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(L10n.t('order.detail.title')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _DetailBody(order: order, symbol: symbol),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(L10n.t('common.ok')),
        ),
        // 补打：等一下打完再关窗（失败会弹"重试 / 跳过"，跟结账那边一样）
        FilledButton.icon(
          onPressed: () async {
            await _reprint(context, order);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          icon: const Icon(Icons.print, size: 20),
          label: Text(L10n.t('order.reprint')),
        ),
      ],
    ),
  );
}

/// 补打小票。成功**不弹提示**（跟别的打印一样），失败才弹「重试 / 跳过」。
Future<void> _reprint(BuildContext context, Order order) async {
  final service = context.read<ReceiptPrintService>();
  final settings = context.read<SettingsController>().settings;

  final err = await service.printReceipt(order, settings);
  if (err == null || !context.mounted) return;
  await showPrintFailureSheet(
    context,
    err,
    () => service.printReceipt(order, settings),
  );
}

/// 明细本体：位置 + 金额 + 结账时间 → 菜品 → 金额明细。
class _DetailBody extends StatelessWidget {
  final Order order;
  final String symbol;

  const _DetailBody({required this.order, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final price = order.price;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- 头：桌号 / 外卖名字 + 金额（大字）+ 支付方式 ----
        Row(
          children: [
            Text(
              orderPlaceLabel(order),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1FA85A),
              ),
            ),
            const Spacer(),
            Text(
              money(order.total, symbol),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF232829),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ---- 结账时间 / 单号 / 收银员 / 支付方式 ----
        _info(L10n.t('order.closedAt'),
            timeShort(closedOrCreatedAt(order))),
        _info(L10n.t('order.id'), order.id),
        if (order.cashier.isNotEmpty)
          _info(L10n.t('pay.cashier'), order.cashier),
        _info(L10n.t('order.method'), orderPaymentLabel(order)),
        const Divider(height: 24),

        // ---- 菜品：昵称 x 份数 … 金额；下面一行小字是选项 / 备注 / 单价 ----
        for (final l in order.lines) _line(l),

        const Divider(height: 24),
        // ---- 金额明细：小计 / 折扣 / 税（有才算）→ 合计 ----
        if (price.hasAdjustments) ...[
          _amount(L10n.t('receipt.labelSubtotal'), order.subtotal),
          if (order.discountAmount != 0)
            _amount(L10n.t('receipt.labelDiscount'), -order.discountAmount),
          if (order.taxAmount != 0)
            _amount(L10n.t('receipt.labelTax'), order.taxAmount),
          const Divider(height: 20),
        ],
        Row(
          children: [
            Text(L10n.t('receipt.labelTotal'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(
              money(order.total, symbol),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  /// 一道菜：**员工看的名字**（有昵称就用昵称，跟购物车 / 厨师单一致）。
  Widget _line(OrderLine l) {
    final unit = l.unit.trim();
    final qty = unit.isEmpty ? '${l.quantity}' : '${l.quantity} $unit';
    final detail = l.detail; // 选项 + 备注
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l.displayName}  ×$qty',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(l.subtotal, symbol),
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
          // 单价 + 选项 / 备注（备注可能很长 → 折行，不省略）
          Text(
            '${money(l.unitPrice, symbol)} / $qty'
            '${detail.isEmpty ? '' : '   ·   $detail'}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, double value) {
    final negative = value < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            '${negative ? '-' : ''}${money(value.abs(), symbol)}',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
