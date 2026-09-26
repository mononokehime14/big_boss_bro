import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../services/sync_service.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../widgets/account_menu.dart';
import '../widgets/admin_gate.dart';
import '../widgets/payment_flow.dart';
import 'daily_summary_screen.dart';

/// 订单页：分「进行中」和「已结单」两个标签页。
/// - 进行中：可点「结账」（折扣/税 + 收款 → 打顾客小票 → 转成已结单）；
///   AA 分开付收过一部分的单会显示「已收 / 仍欠」。
/// - 已结单：可删除（**需要管理员权限**）。
/// 右上角有「日结」（也需要管理员权限），打开每日汇总。
///
/// 注：切到这一页时 `HomeShell` 会顺手同步一次（多设备一个单池，看到的就是最新的）。
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final open = pos.inProgressOrders;
    final closed = pos.completedOrders;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t('order.history.title')),
          actions: [
            // 后台同步状态：待上传几张 + 点一下立刻同步
            const _SyncButton(),
            // 日结（每日汇总 + 打印）：管理员的地方
            TextButton.icon(
              onPressed: () async {
                final ok = await requireAdmin(
                  context,
                  reason: L10n.t('auth.summaryNeeded'),
                );
                if (!ok || !context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DailySummaryScreen()),
                );
              },
              icon: const Icon(Icons.summarize_outlined, size: 18),
              label: Text(L10n.t('summary.title')),
            ),
            const AccountMenuButton(),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: '${L10n.t('order.status.inProgress')} (${open.length})'),
              Tab(text:
                  '${L10n.t('order.status.completed')} (${closed.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrderList(orders: open, inProgress: true),
            _OrderList(orders: closed, inProgress: false),
          ],
        ),
      ),
    );
  }
}

/// 订单页右上角的**同步按钮**：显示「待上传 N」+ 点一下立刻同步。
///
/// 没启用后台同步时**整块隐藏**（不用的是大多数情况，别占地方）。
class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    if (!settings.syncEnabled) return const SizedBox.shrink();
    final sync = context.watch<SyncService>();
    final status = sync.status;
    final pending = status.pendingOrders;
    final err = status.error;
    // 开关开了但还没填全 → 点它也要说清楚为什么没动静
    final blocked = sync.syncBlockedReason;

    return Tooltip(
      message: blocked != null
          ? L10n.t(blocked)
          : (err != null
              ? '${L10n.t('sync.error')}: $err'
              : '${L10n.t('sync.lastAt')}: '
                  '${status.lastSyncAt == null ? L10n.t('sync.never') : timeShort(status.lastSyncAt!)}'
                  '   ·   ${L10n.t('sync.pending')}: $pending'),
      child: TextButton.icon(
        onPressed: sync.busy
            ? null
            : () {
                if (blocked != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.t(blocked))),
                  );
                  return;
                }
                sync.syncNow();
              },
        icon: sync.busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                (err != null || blocked != null)
                    ? Icons.cloud_off_outlined
                    : (pending > 0
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined),
                size: 18,
                color: (err != null || blocked != null)
                    ? Colors.red.shade400
                    : null,
              ),
        label: Text(
          pending > 0
              ? '${L10n.t('sync.short')} $pending'
              : L10n.t('sync.short'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final bool inProgress;


  const _OrderList({required this.orders, required this.inProgress});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyOrders(
        text: inProgress
            ? L10n.t('cart.noOrders')
            : L10n.t('order.history.empty'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _OrderCard(
        order: orders[i],
        inProgress: inProgress,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final bool inProgress;

  const _OrderCard({required this.order, required this.inProgress});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final currency = settings.currencySymbol;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 桌号 / 单子类型（醒目）：堂食显示桌号，外卖 / 电话外卖显示类型
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1FA85A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.isPhoneTakeaway
                        ? L10n.t('order.phonecallTakeaway')
                        : order.isTakeaway
                            ? L10n.t('order.takeaway')
                            : '${L10n.t('order.table')} '
                                '${order.table.isEmpty ? '-' : order.table}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1FA85A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${order.itemCount} ${L10n.t('cart.items')}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                // 还没推上后台的单：橙色小标记（一眼看出后台可能还没收到）
                if (order.dirty && settings.syncEnabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      L10n.t('sync.notUploaded'),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFEF6C00)),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  money(order.total, currency),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1FA85A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${L10n.t('order.id')} ${order.id}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  _formatTime(order.createdAt),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (!inProgress) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.payments_outlined,
                      size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _paymentLabel(order),
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            // 菜名摘要
            Text(
              order.lines.map((l) => '${l.name}×${l.quantity}').join('，'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            // 外币收款：币种 / 汇率 / 该币种应收 / 实收 / 找零
            if (order.isForeignCurrency) ...[
              const SizedBox(height: 6),
              Text(
                _foreignLine(order, currency),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1565C0),
                ),
              ),
            ],
            // 折扣 / 税（有才显示）
            if (order.price.hasAdjustments) ...[
              const SizedBox(height: 4),
              Text(
                [
                  '${L10n.t('receipt.labelSubtotal')} ${money(order.subtotal, currency)}',
                  if (order.discountAmount != 0)
                    '${L10n.t('receipt.labelDiscount')} ${order.discountLabel(currency)} '
                        '-${money(order.discountAmount, currency)}',
                  if (order.taxAmount != 0)
                    '${L10n.t('receipt.labelTax')} ${money(order.taxAmount, currency)}',
                ].join('  ·  '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  tooltip: L10n.t('order.delete'),
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                ),
                if (inProgress)
                  FilledButton(
                    onPressed: () => settleOrderFlow(context, order),
                    child: Text(L10n.t('order.settle')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 删除订单：**要管理员权限**（删掉就没有记录，是危险操作）。
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await requireAdmin(
      context,
      reason: L10n.t('auth.deleteNeeded'),
    );
    if (!ok || !context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('order.delete.confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () {
              context.read<PosController>().deleteOrder(order.id);
              Navigator.pop(dialogContext);
            },
            child: Text(
              L10n.t('common.delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(PaymentMethod? m) {
    switch (m) {
      case PaymentMethod.cash:
        return L10n.t('payment.cash');
      case PaymentMethod.card:
        return L10n.t('payment.card');
      case PaymentMethod.qr:
        return L10n.t('payment.qr');
      case null:
        return '-';
    }
  }

  /// 支付方式显示：混付（老数据）就写「混合」。
  String _paymentLabel(Order order) {
    final methods = order.payments.map((p) => p.method).toSet();
    if (methods.length > 1) return L10n.t('payment.mixed');
    return _methodLabel(order.paymentMethod);
  }

  /// 外币收款那一行：`USD  1 = ¥18.50  ·  应收 $31.15  ·  实收 $40.00  ·  找零 $8.85`
  String _foreignLine(Order order, String baseCurrency) {
    final sym = kCurrencySymbols[order.currencyCode] ?? '';
    String amt(double v) => '$sym${v.toStringAsFixed(2)}';
    final parts = <String>[
      '${order.currencyCode}  '
          '1 = ${money(order.exchangeRate, baseCurrency)}',
      '${L10n.t('pay.due')} ${amt(order.foreignDue(order.exchangeRate))}',
    ];
    if (order.receivedAmount != null) {
      parts.add('${L10n.t('pay.received')} ${amt(order.receivedAmount!)}');
    }
    if (order.changeAmount != null && order.changeAmount != 0) {
      parts.add('${L10n.t('pay.change')} ${amt(order.changeAmount!)}');
    }
    return parts.join('  ·  ');
  }

  String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _EmptyOrders extends StatelessWidget {
  final String text;
  const _EmptyOrders({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
