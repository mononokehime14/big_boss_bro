import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../widgets/payment_flow.dart';

/// 订单页：分「进行中」和「已结单」两个标签页。
/// - 进行中：可点「结账」（选支付方式 → 打顾客小票 → 转成已结单）。
/// - 已结单：可删除。
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
                // 桌号（醒目）
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1FA85A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${L10n.t('order.table')} ${order.table.isEmpty ? '-' : order.table}',
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
                    _methodLabel(order.paymentMethod),
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

  void _confirmDelete(BuildContext context) {
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
            child: Text(L10n.t('common.delete')),
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
