import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/format.dart';

/// 购物车面板（可放在右侧常驻，也可放进底部弹窗）。
///
/// 里面包含：条目列表（改数量/删除）、桌号或「追加到已有单」的选择、
/// 合计、以及「下单 / 追加」按钮。点击按钮时通过 [onSubmit] 回调出去，
/// 由外层决定后续（打印厨房单等）。
class CartPanel extends StatefulWidget {
  final void Function(bool isAppend, String table, String? appendOrderId)
      onSubmit;

  /// 是否显示顶部拖动条（放进底部弹窗时为 true）。
  final bool showHandle;

  const CartPanel({
    super.key,
    required this.onSubmit,
    this.showHandle = false,
  });

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  bool _isAppend = false;
  String _table = '';
  String? _appendOrderId;

  @override
  void initState() {
    super.initState();
    final tables = context.read<SettingsController>().settings.tables;
    _table = tables.isNotEmpty ? tables.first : '';
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final tables = settings.tables;
    final openOrders = pos.inProgressOrders;

    // 桌号被删掉就回退到第一个
    if (tables.isNotEmpty && !tables.contains(_table)) {
      _table = tables.first;
    }
    // 追加目标不存在就清空
    if (_appendOrderId != null &&
        !openOrders.any((o) => o.id == _appendOrderId)) {
      _appendOrderId = null;
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          if (widget.showHandle) ...[
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                const SizedBox(width: 8),
                Text(
                  '${pos.cartCount} ${L10n.t('cart.items')}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (!pos.cartEmpty)
                  TextButton.icon(
                    onPressed: pos.clearCart,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(L10n.t('cart.clear')),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pos.cartEmpty
                ? _EmptyCart()
                : ListView.separated(
                    itemCount: pos.cartItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _CartLine(cartKey: pos.cartItems[i].key),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _targetSelector(tables, openOrders),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(L10n.t('cart.total'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  money(pos.cartTotal, settings.currencySymbol),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1FA85A),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: pos.cartEmpty
                    ? null
                    : () => _submit(tables, openOrders),
                child: Text(_isAppend
                    ? L10n.t('cart.append')
                    : L10n.t('cart.placeOrder')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「新单 + 桌号」或「追加到已有单」二选一。
  Widget _targetSelector(List<String> tables, List<Order> openOrders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChoiceChip(
              selected: !_isAppend,
              onSelected: (_) => setState(() => _isAppend = false),
              label: Text(L10n.t('cart.newOrder')),
              showCheckmark: false,
              selectedColor: const Color(0xFF1FA85A),
              labelStyle: TextStyle(
                color: _isAppend ? const Color(0xFF232829) : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              selected: _isAppend,
              onSelected: (_) => setState(() => _isAppend = true),
              label: Text(L10n.t('cart.appendToOrder')),
              showCheckmark: false,
              selectedColor: const Color(0xFF1FA85A),
              labelStyle: TextStyle(
                color: _isAppend ? Colors.white : const Color(0xFF232829),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_isAppend) ...[
          Text(L10n.t('order.table'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: tables.contains(_table) ? _table : null,
            isExpanded: true,
            hint: Text(L10n.t('cart.noOrders')),
            items: tables
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _table = v);
            },
          ),
        ] else if (openOrders.isEmpty)
          Text(
            L10n.t('cart.noOrders'),
            style: TextStyle(color: Colors.grey.shade600),
          )
        else ...[
          Text(L10n.t('cart.appendToOrder'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: _appendOrderId,
            isExpanded: true,
            hint: Text(L10n.t('cart.appendToOrder')),
            items: openOrders
                .map((o) => DropdownMenuItem(
                      value: o.id,
                      child: Text(
                        '${o.table.isEmpty ? '-' : o.table} · ${o.itemCount}${L10n.t('cart.items')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _appendOrderId = v),
          ),
        ],
      ],
    );
  }

  void _submit(List<String> tables, List<Order> openOrders) {
    if (_isAppend) {
      if (_appendOrderId == null) {
        _snack(L10n.t('cart.noOrders'));
        return;
      }
    } else if (tables.isEmpty) {
      _snack(L10n.t('cart.noOrders'));
      return;
    }
    widget.onSubmit(_isAppend, _table, _appendOrderId);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CartLine extends StatelessWidget {
  /// 购物车行的唯一键（菜 + 选项 + 备注），见 `CartItem.key`。
  final String cartKey;

  const _CartLine({required this.cartKey});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final item = pos.cartItems.firstWhere((c) => c.key == cartKey);

    // 用「分类颜色」的小圆点代替图案（和点单页保持一致）
    final catIndex =
        pos.categories.indexWhere((c) => c.id == item.menuItem.categoryId);
    final dotColor = Color(catIndex >= 0
        ? categoryColorAt(pos.categories[catIndex].colorValue, catIndex)
        : 0xFF1FA85A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.menuItem.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                // 选项 / 备注（有才显示）
                if (item.detail.isNotEmpty)
                  Text(
                    item.detail,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1FA85A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  money(item.menuItem.price, settings.currencySymbol),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          _Stepper(
            quantity: item.quantity,
            onMinus: () => pos.decrement(cartKey),
            onPlus: () => pos.increment(cartKey),
          ),
          SizedBox(
            width: 70,
            child: Text(
              money(item.lineTotal, settings.currencySymbol),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: () => pos.removeFromCart(cartKey),
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _Stepper({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline,
              size: 20, color: Color(0xFF1FA85A)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined,
                size: 44, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              L10n.t('cart.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
