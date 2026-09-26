import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/format.dart';
import '../utils/pricing.dart';
import 'item_customize_dialog.dart';

/// 购物车面板（宽屏常驻右侧，窄屏放进底部弹窗）。
///
/// 结构（从上到下）：
/// 1. **桌号 / 外卖下拉**（堂食外卖出这里选；有菜的桌子显示橙色 +「已有 N」）；
/// 2. **已在单上**：这张桌**当前这张单**里的菜（选桌后自动带出来）。
///    其中**已经下过厨房**的用绿色 +「已下厨」标出来，
///    「保存」过但还没送厨房的用橙色 +「未下厨」标出来（只读）；
/// 3. **本次新增**：刚点的菜（可以加减份数、删除）；
/// 4. **合计**（整桌 = 已在单上 + 本次新增）和下面两个按钮：
///    **左「保存」**（只记到单上，不打单）/ **右「厨房」**（记到单上 + 打厨房单）。
///
/// 结账不在这里：去「订单」页选进行中的单结账（逻辑没变）。
class CartPanel extends StatefulWidget {
  /// 左按钮「保存」：只把本次新增的菜记到单上，不打厨房单。
  final VoidCallback onSave;

  /// 右按钮「厨房」：记到单上，并把这张单上**没下厨的菜**打一张厨房单。
  final VoidCallback onKitchen;

  /// 是否显示顶部拖动条（放进底部弹窗时为 true）。
  final bool showHandle;

  const CartPanel({
    super.key,
    required this.onSave,
    required this.onKitchen,
    this.showHandle = false,
  });

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  @override
  void initState() {
    super.initState();
    // 还没选桌就先默认选第一张桌，保证「保存 / 厨房」一直可用（用户可以随时在下拉里换）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pos = context.read<PosController>();
      if (pos.hasTableSelected) return;
      final tables = context.read<SettingsController>().settings.tables;
      if (tables.isNotEmpty) pos.selectTable(tables.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final open = pos.openOrderForSelectedTable();
    final placed = open?.lines ?? const <OrderLine>[];
    final unsent = placed.where((l) => !l.sentToKitchen).length;
    /// 这张桌**当前进行中那张单**的 id（没有单时是空串；下面的按钮只在有菜时可点）。
    final orderId = open?.id ?? '';

    // 整桌合计 = 「已在单上」的小计 + 购物车里新增的小计，
    // 按**这张单自己的**折扣/税快照算（没有单就用设置里的），
    // 这样这个数字 = 保存后订单的应收 = 最后结账收的钱。
    final price = PriceBreakdown.of(
      subtotal: (open?.subtotal ?? 0) + pos.cartSubtotal,
      discountType: open?.discountType ?? DiscountType.none,
      discountValue: open?.discountValue ?? 0,
      taxRate: open?.taxRate ?? settings.taxRate,
      taxIncluded: open?.taxIncluded ?? settings.taxIncluded,
    );

    final hasAnything = placed.isNotEmpty || !pos.cartEmpty;

    // 两个按钮**分别**判断能不能点（之前两个共用一个条件，导致「先点保存就再也打不了厨房」）：
    // - 「保存」：要购物车里有**新菜**；
    // - 「厨房」：只要有**还没下厨的菜**就行 —— 包括先点「保存」留在单上的那些
    //   （这时购物车是空的，但单上还有未下厨的菜，仍然要能打给厨房）。
    final canSave = pos.hasTableSelected && !pos.cartEmpty;
    final canKitchen = pos.hasTableSelected && (!pos.cartEmpty || unsent > 0);

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
          // ---- 目标桌号 / 外卖（下拉选择；有菜的桌子用颜色标出来）----
          _targetSelector(pos, open, unsent),
          const Divider(height: 1),
          Expanded(
            child: !hasAnything
                ? _EmptyCart()
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // ---- 已在单上：这张单现在的菜（下过厨房的标绿，也能改）----
                      if (placed.isNotEmpty) ...[
                        _sectionHeader(
                          icon: Icons.receipt_long_outlined,
                          title: L10n.t('cart.onOrder'),
                          trailing:
                              '${open?.itemCount ?? 0} ${L10n.t('cart.items')}',
                        ),
                        for (var i = 0; i < placed.length; i++)
                          _PlacedLine(
                            line: placed[i],
                            currency: settings.currencySymbol,
                            canDelete: placed.length > 1,
                            // 点这一行 → 回到「点菜」编辑框（选项 / 备注 / 份数）
                            onTap: () => _editPlacedLine(orderId, i),
                            onMinus: () => _changeQty(orderId, i, -1),
                            onPlus: () => _changeQty(orderId, i, 1),
                            onDelete: () => _deletePlacedLine(orderId, i),
                          ),
                      ],
                      // ---- 本次新增：刚点的菜（点一下也能回去改）----
                      if (!pos.cartEmpty) ...[
                        _sectionHeader(
                          icon: Icons.add_shopping_cart,
                          title: L10n.t('cart.newItems'),
                          trailing:
                              '${pos.cartCount} ${L10n.t('cart.items')}',
                          action: TextButton.icon(
                            onPressed: pos.clearCart,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(L10n.t('cart.clear')),
                          ),
                        ),
                        for (final c in pos.cartItems)
                          _CartLine(
                            cartKey: c.key,
                            onEdit: () => _editCartLine(c),
                          ),
                      ],
                      const SizedBox(height: 6),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                // 有税（或价外税）时多显示 小计 / 税 两行，避免客人觉得金额对不上
                if (price.hasTax) ...[
                  _miniRow(L10n.t('receipt.labelSubtotal'),
                      money(price.subtotal, settings.currencySymbol)),
                  _miniRow(
                    '${L10n.t('receipt.labelTax')} '
                    '${settings.taxRate.toStringAsFixed(settings.taxRate == settings.taxRate.roundToDouble() ? 0 : 2)}%'
                    '${settings.taxIncluded ? ' (${L10n.t('tax.included')})' : ''}',
                    money(price.tax, settings.currencySymbol),
                  ),
                ],
                Row(
                  children: [
                    Text(
                      placed.isEmpty
                          ? L10n.t('cart.total')
                          : L10n.t('cart.totalTable'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      money(price.total, settings.currencySymbol),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1FA85A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---- 购物车下面两个按钮：左「保存」/ 右「厨房」----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canSave ? widget.onSave : null,
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: Text(L10n.t('cart.save')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canKitchen ? widget.onKitchen : null,
                    icon: const Icon(Icons.restaurant, size: 20),
                    label: Text(L10n.t('cart.kitchen')),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              L10n.t('cart.buttonsHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 「已在单上」的菜：点一下能改，也能删 ----------------
  //
  // 改动都**只改账单**（你选的方案）：不给厨房补打变动单；
  // 被改过的行会自动变回「未下厨」，下次点「厨房」会重新打给它。

  /// 点「已在单上」的某一行 → 回到点菜编辑框（选项 / 特别备注 / 份数）。
  Future<void> _editPlacedLine(String orderId, int index) async {
    final pos = context.read<PosController>();
    final order = pos.findOrder(orderId);
    if (order == null || index >= order.lines.length) return;
    final line = order.lines[index];
    final item = pos.menuItemForLine(line);

    final result = await showItemCustomizeDialog(
      context,
      item,
      title: line.name,
      initial: ItemEditResult(
        selections: line.options,
        notes: line.notes,
        quantity: line.quantity,
      ),
    );
    if (result == null || !mounted) return;
    pos.updateOrderLine(
      orderId,
      index,
      selections: result.selections,
      notes: result.notes,
      quantity: result.quantity,
    );
  }

  /// 「已在单上」的 +/-（减到 0 等于删掉这一行）。
  void _changeQty(String orderId, int index, int delta) {
    context.read<PosController>().changeOrderLineQuantity(orderId, index, delta);
  }

  /// 「已在单上」的 ✕：先弹一次确认再删（防误触）。
  Future<void> _deletePlacedLine(String orderId, int index) async {
    final pos = context.read<PosController>();
    final order = pos.findOrder(orderId);
    if (order == null || index >= order.lines.length) return;
    if (order.lines.length <= 1) return; // 最后一道菜不给删（兜底，按钮已禁用）

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('cart.deleteConfirm')),
        content: Text(order.lines[index].name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    pos.removeOrderLine(orderId, index);
  }

  /// 点「本次新增」的某一行 → 回到点菜编辑框，保存后替换这一行。
  Future<void> _editCartLine(CartItem item) async {
    final pos = context.read<PosController>();
    final result = await showItemCustomizeDialog(
      context,
      item.menuItem,
      initial: ItemEditResult(
        selections: item.selections,
        notes: item.notes,
        quantity: item.quantity,
      ),
    );
    if (result == null || !mounted) return;
    pos.updateCartItem(
      item.key,
      selections: result.selections,
      notes: result.notes,
      quantity: result.quantity,
    );
  }

  /// 分区小标题（「已在单上」/「本次新增」）。
  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String trailing,
    Widget? action,
  }) =>
      Container(
        color: const Color(0xFFF7F9F8),
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            if (action != null) action,
          ],
        ),
      );

  /// 顶部：**桌号 / 外卖下拉**（堂食外卖出这里选）。
  ///
  /// 下拉里每张桌带一个状态：**有菜的桌子橙色 +「已有 N」**，空桌绿色；
  /// 下面一行是当前目标的状态：`已有 3 件 · 未下厨 1`（说明还有几个菜没送厨房）。
  Widget _targetSelector(PosController pos, Order? open, int unsent) {
    final settings = context.watch<SettingsController>().settings;
    final tables = settings.tables;
    final value = pos.isPhoneTakeaway
        ? _kPhoneTakeaway
        : pos.isTakeaway
            ? _kTakeaway
            : (tables.contains(pos.selectedTable) ? pos.selectedTable : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t('order.table'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(L10n.t('table.pickShort')),
            items: [
              // 外卖
              DropdownMenuItem(
                value: _kTakeaway,
                child: _targetRow(
                  L10n.t('order.takeaway'),
                  color: const Color(0xFF37474F),
                  note: pos.openTakeawayCount > 0
                      ? '${pos.openTakeawayCount} ${L10n.t('table.openOrders')}'
                      : null,
                ),
              ),
              // 电话外卖（打电话点的，也单独统计）
              DropdownMenuItem(
                value: _kPhoneTakeaway,
                child: _targetRow(
                  L10n.t('order.phonecallTakeaway'),
                  color: const Color(0xFF6A1B9A),
                  note: pos.openPhoneTakeawayCount > 0
                      ? '${pos.openPhoneTakeawayCount} ${L10n.t('table.openOrders')}'
                      : null,
                ),
              ),
              // 各桌（有菜 = 橙色，空桌 = 绿色）
              for (final t in tables)
                DropdownMenuItem<String>(
                  value: t,
                  child: _targetRow(
                    '${L10n.t('order.table')} $t',
                    color: pos.openItemCountForTable(t) > 0
                        ? const Color(0xFFEF6C00)
                        : const Color(0xFF2E7D32),
                    note: pos.openItemCountForTable(t) > 0
                        ? '${L10n.t('table.already')} ${pos.openItemCountForTable(t)}'
                        : null,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == _kTakeaway) {
                pos.selectTable('', takeaway: true);
              } else if (v == _kPhoneTakeaway) {
                // 电话外卖：不用桌号，跟外卖一样每单独立，只是标签/统计分开
                pos.selectTable('',
                    takeaway: true, type: OrderType.phonecallTakeaway);
              } else {
                pos.selectTable(v);
              }
            },
          ),
          // 当前目标的状态说明（已有几个菜 / 其中几个还没下厨 / 空桌）
          Text(
            open != null
                ? '${L10n.t('table.already')} ${open.itemCount} ${L10n.t('cart.items')}'
                    '${unsent > 0 ? ' · ${L10n.t('cart.unsent')} $unsent' : ''}'
                : (pos.isTakeaway
                    ? L10n.t('cart.takeawayHint')
                    : L10n.t('table.empty')),
            style: TextStyle(
              fontSize: 12,
              color: open != null
                  ? const Color(0xFFEF6C00)
                  : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 小计 / 税 这类小号金额行。
  Widget _miniRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
          ],
        ),
      );

  /// 下拉里的一行：颜色圆点 + 名称 (+ 备注)。
  Widget _targetRow(String label, {required Color color, String? note}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        if (note != null)
          Text(
            note,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// 下拉里代表「外卖」的伪桌号。
const String _kTakeaway = '__takeaway__';

/// 下拉里代表「**电话外卖**」的伪桌号（打电话来点的外卖）。
const String _kPhoneTakeaway = '__phone_takeaway__';

class _CartLine extends StatelessWidget {
  /// 购物车行的唯一键（菜 + 选项 + 备注），见 `CartItem.key`。
  final String cartKey;

  /// 点这一行 → 回到点菜编辑框（选项 / 特别备注 / 份数）。
  final VoidCallback onEdit;

  const _CartLine({required this.cartKey, required this.onEdit});

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

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
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
                    // 单价（+ 单位，例如「¥140.00 / 份」）· 点这一行可以改
                    '${item.menuItem.hasUnit ? '${money(item.unitPrice, settings.currencySymbol)} / ${item.menuItem.unit}' : money(item.unitPrice, settings.currencySymbol)}'
                    ' · ${L10n.t('cart.tapToEdit')}',
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
      ),
    );
  }
}

/// 「已在单上」的一行：**已经记在这张桌的单里**。
///
/// **点这一行**回到点菜编辑框（选项 / 特别备注 / 份数），右边还有 +/− 和 ✕。
/// 改动只改账单（不给厨房补打变动单）；被改过的行会自动变回「未下厨」，
/// 下次点「厨房」会重新打给它。
///
/// 颜色就是「下没下厨房」的标记：
/// - **已下厨**：浅绿底 + 绿色竖条 + 绿色「已下厨」小标签（厨房已经收到了）；
/// - **未下厨**：浅橙底 + 橙色竖条 + 橙色「未下厨」小标签（只是「保存」过，
///   还没打给厨房，下次点「厨房」会一起送过去）。
class _PlacedLine extends StatelessWidget {
  final OrderLine line;
  final String currency;

  /// 只剩最后一道菜时不给删。
  final bool canDelete;

  final VoidCallback onTap;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onDelete;

  const _PlacedLine({
    required this.line,
    required this.currency,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onDelete,
    this.canDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final symbol = currency;
    final sent = line.sentToKitchen;

    final accent = sent ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00);
    final bg = sent ? const Color(0xFFF1F8F3) : const Color(0xFFFFF6E9);
    final badgeBg = sent ? const Color(0xFFE0F0E5) : const Color(0xFFFFEBD5);

    final detail = <String>[
      if (line.options.isNotEmpty) line.options.join(' / '),
      if (line.note.trim().isNotEmpty) line.note.trim(),
    ].join(' · ');

    return Container(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
          child: Row(
            children: [
              // 左边的竖色条：一眼分得出「下过厨房」还是「只是保存了」
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            line.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: sent
                                  ? Colors.grey.shade700
                                  : const Color(0xFF232829),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          sent ? L10n.t('cart.sent') : L10n.t('cart.unsent'),
                          accent,
                          badgeBg,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${money(line.unitPrice, symbol)}'
                      '${line.unit.trim().isEmpty ? '' : ' / ${line.unit.trim()}'}'
                      '${detail.isEmpty ? '' : ' · $detail'}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _Stepper(
                quantity: line.quantity,
                onMinus: onMinus,
                onPlus: onPlus,
              ),
              SizedBox(
                width: 70,
                child: Text(
                  money(line.subtotal, symbol),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        sent ? Colors.grey.shade700 : const Color(0xFF232829),
                  ),
                ),
              ),
              IconButton(
                onPressed: canDelete ? onDelete : null,
                tooltip: canDelete
                    ? L10n.t('cart.deleteLine')
                    : L10n.t('cart.deleteLast'),
                icon: const Icon(Icons.close, size: 18),
                color: Colors.grey,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, Color background) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
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
