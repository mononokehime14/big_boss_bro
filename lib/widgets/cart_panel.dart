import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart';
import '../l10n/app_strings.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../screens/split_bill_screen.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/menu_sort.dart';
import '../utils/order_label.dart';
import '../utils/pricing.dart';
import 'custom_item_dialog.dart';
import 'item_customize_dialog.dart';
import 'move_order_dialog.dart';
import 'takeaway_name_dialog.dart';

/// 购物车面板（宽屏常驻右侧，窄屏放进底部弹窗）。
///
/// 结构（从上到下）：
/// 1. **桌号 / 外卖下拉**（堂食外卖出这里选；有菜的桌子显示橙色 +「已有 N」），
///    右边一个「**⋮**」：**清空购物车**这类用得少的操作放在里面；
/// 2. **已在单上**：这张桌**当前这张单**里的菜（选桌后自动带出来）。
///    其中**已经下过厨房**的用绿色 +「已下厨」标出来，
///    「保存」过但还没送厨房的用橙色 +「未下厨」标出来（只读）；
/// 3. **本次新增**：刚点的菜（**点一行**回点菜框里改选项 / 备注 / 份数）；
/// 4. **合计**（整桌 = 已在单上 + 本次新增）和下面三个按钮：
///    **保存 / 厨房 / 结账**（结账 = 记单之后直接开这张单的结账窗口）。
///
/// 列里**只留必要信息**（安卓小屏实测：字大 + 多余提示会把票面挤得看不下）：
/// 每行 = 菜名（+ 选项 / 备注）+ `×份数` + 金额 + ✕；
/// 份数**只显示不加减**，要改就点这一行进点菜框改数字。
///
/// 下面三个按钮：**保存 / 厨房 / 结账** —— 屏幕窄到放不下文字时**只显示图标**
/// （长按有提示），见 [_CartPanelState._actionButtons]。
class CartPanel extends StatefulWidget {
  /// 左按钮「保存」：只把本次新增的菜记到单上，不打厨房单。
  final VoidCallback onSave;

  /// 中按钮「厨房」：记到单上，并把这张单上**没下厨的菜**打一张厨房单。
  final VoidCallback onKitchen;

  /// 右按钮「结账」：记到单上，然后**直接打开这张单的结账窗口**
  /// （外卖客人当场点完就付钱的那种，不用再绕到订单页）。
  final VoidCallback onCheckout;

  /// 是否显示顶部拖动条（放进底部弹窗时为 true）。
  final bool showHandle;

  const CartPanel({
    super.key,
    required this.onSave,
    required this.onKitchen,
    required this.onCheckout,
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
    final unsent = placed.where((l) => l.unsentQty > 0).length;
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

    // 三个按钮**分别**判断能不能点（之前两个共用一个条件，导致「先点保存就再也打不了厨房」）：
    // - 「保存」：**只要有桌/外卖就能点，不限次数**（想保存就保存）；
    //   购物车是空的也没关系 —— 那等于"再确认一次这张单"（没有新菜就什么都不变）。
    // - 「厨房」：只要有**还没下厨的菜**就行 —— 包括先点「保存」留在单上的那些
    //   （这时购物车是空的，但单上还有未下厨的菜，仍然要能打给厨房）；
    // - 「结账」：购物车里有新菜，**或者**当前这张单/刚动过的那张单还没结
    //   （那种"菜都下过厨房了、就等收钱"的情况也要能结）。
    final canSave = pos.hasTableSelected;
    final canKitchen = pos.hasTableSelected && (!pos.cartEmpty || unsent > 0);
    final canCheckout = pos.hasTableSelected &&
        (!pos.cartEmpty || open != null || pos.lastTouchedOrder != null);

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
          _targetSelector(pos, open),
          const Divider(height: 1),
          Expanded(
            child: !hasAnything
                ? _EmptyCart()
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // ---- 已在单上：这张单现在的菜 ----
                      // **不再打「已下厨 / 未下厨」那几个字**（安卓小屏实测太费地方）：
                      // 每行只留 菜名（+ 选项/备注）+ `×份数` + ✕，菜名能占到 70% 以上；
                      // 下没下厨房**靠底色区分**（不占空间）：已下厨浅绿、还有份数没打给厨房浅黄
                      // （并单之后一行里可能"厨房收了 1 份、还有 1 份没打"，这种算未下厨）。
                      if (placed.isNotEmpty) ...[
                        for (var i = 0; i < placed.length; i++)
                          _LineRow(
                            name: placed[i].displayName,
                            detail: placed[i].detail,
                            quantity: placed[i].quantity,
                            // 这一行的钱（含备注加价「换炒饭 +70」）
                            amount: money(placed[i].subtotal,
                                settings.currencySymbol),
                            background: placed[i].sentToKitchen
                                ? _kSentBg
                                : _kUnsentBg,
                            // 点这一行 → 回到「点菜」编辑框（选项 / 备注 / 份数）
                            onTap: () => _editPlacedLine(orderId, i),
                            // ✕ 一直可点：**最后一道菜删掉 = 整张单删掉**（会弹确认）
                            canDelete: true,
                            onDelete: () => _deletePlacedLine(orderId, i),
                          ),
                      ],
                      // ---- 本次新增：刚点的菜（点一下也能回去改）----
                      // 小标题只留「本次新增」四个字：**件数**和「清空」都不在这儿了
                      // （清空进了桌号旁边的「⋮」），把地方全让给菜名。
                      if (!pos.cartEmpty) ...[
                        _sectionHeader(
                          icon: Icons.add_shopping_cart,
                          title: L10n.t('cart.newItems'),
                        ),
                        for (final c in pos.cartItems)
                          _LineRow(
                            name: c.menuItem.displayName,
                            detail: c.detail,
                            quantity: c.quantity,
                            // 这一行的钱（含备注加价「换炒饭 +70」）
                            amount: money(c.lineTotal, settings.currencySymbol),
                            onTap: () => _editCartLine(c),
                            onDelete: () => pos.removeFromCart(c.key),
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
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      money(price.total, settings.currencySymbol),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1FA85A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---- 购物车下面三个按钮：左「保存」/ 中「厨房」/ 右「结账」----
          // 屏幕窄（手机 / 小屏平板）放不下三行字的时候**只显示图标**（长按有提示），
          // 免得文字被挤成省略号、或者换行把按钮撑高 —— 见 [_actionButtons]。
          _actionButtons(
            canSave: canSave,
            canKitchen: canKitchen,
            canCheckout: canCheckout,
          ),
          // （原来这里有一行「保存/厨房 分别是干嘛的」说明文字，去掉了：按钮名字够清楚）
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  // ---------------- 下面三个按钮（放不下字就只剩图标） ----------------

  /// 三个按钮：**保存 / 厨房 / 结账**。
  ///
  /// **屏幕窄就只显示图标**（安卓小屏实测：三个按钮挤在一行，文字会被压成 `…`、
  /// 甚至换行把按钮撑高）。判断方法很实在 —— 用 [TextPainter] 把三行字
  /// **在当前主题字号 / 系统字体缩放下**量出来，加上图标、间距、内边距，
  /// 跟这一行实际宽度比一比：放得下就「图标 + 文字」，放不下就只剩图标。
  ///
  /// 只剩图标时外面套 [Tooltip]：**长按**能看到这是哪个按钮（无障碍也不会丢信息）。
  Widget _actionButtons({
    required bool canSave,
    required bool canKitchen,
    required bool canCheckout,
  }) {
    const labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    const iconSize = 20.0;
    const iconGap = 6.0;
    const innerPad = 8.0; // 每个按钮左右各留 8
    const buttonGap = 8.0;
    const barPad = 12.0; // 三个按钮那一行的左右外边距

    final saveLabel = L10n.t('cart.save');
    final kitchenLabel = L10n.t('cart.kitchen');
    final checkoutLabel = L10n.t('cart.checkout');

    return LayoutBuilder(
      builder: (context, constraints) {
        // 这一行里每个按钮能分到多少宽（flex 2 : 3 : 3 → 一共 8 份）
        final avail =
            constraints.maxWidth - barPad * 2 - buttonGap * 2;
        double need(String label) =>
            iconSize +
            iconGap +
            _textWidth(context, label, labelStyle) +
            2 * innerPad +
            4; // 余量：贴着边会显得挤，宁可早点收成图标

        // 三个里**任意一个**放不下「图标 + 文字」→ 三个都只剩图标
        // （只给一个去掉文字会很难看，而且图标本身也很好认）
        final iconsOnly = avail * 2 / 8 < need(saveLabel) ||
            avail * 3 / 8 < need(kitchenLabel) ||
            avail * 3 / 8 < need(checkoutLabel);

        Widget content(IconData icon, String label) => iconsOnly
            ? Tooltip(
                message: label, // 只有图标时，长按能看见这是什么
                child: Icon(icon, size: iconSize + 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize),
                  const SizedBox(width: iconGap),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

        return Padding(
          padding: EdgeInsets.fromLTRB(barPad, 4, barPad, 6),
          child: Row(
            children: [
              // 「保存」窄一点（`flex: 2`），把地方让给「厨房」和「结账」——
              // 后两个是真正"要动手"的：一个出厨房单、一个收钱。
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: canSave ? widget.onSave : null,
                  style: OutlinedButton.styleFrom(
                    // 跟旁边两个实心按钮**一样高**（实心按钮的高度来自主题的 52）
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: innerPad),
                    textStyle: labelStyle,
                  ),
                  child: content(Icons.save_outlined, saveLabel),
                ),
              ),
              const SizedBox(width: buttonGap),
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: canKitchen ? widget.onKitchen : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: innerPad),
                    textStyle: labelStyle,
                  ),
                  child: content(Icons.restaurant, kitchenLabel),
                ),
              ),
              const SizedBox(width: buttonGap),
              // 结账：外卖客人当场点完就付钱 —— 记单之后直接开结账窗口
              // （颜色用深蓝，跟「厨房」的绿区分开，不至于点错）
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: canCheckout ? widget.onCheckout : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    // 三个按钮**一样高**（显式写出来，免得跟主题的 52 打架）
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: innerPad),
                    textStyle: labelStyle,
                  ),
                  child: content(Icons.point_of_sale, checkoutLabel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 量一段文字在**当前主题 + 系统字体缩放**下有多宽（判断按钮放不放得下字）。
  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  // ---------------- 「已在单上」的菜：点一下能改，也能删 ----------------
  //
  // 改动都**只改账单**（你选的方案）：不给厨房补打变动单；
  // 被改过的行会自动变回「未下厨」，下次点「厨房」会重新打给它。

  /// 改外卖单的**名字 / 等待时间**（那个「等 N 分钟」chip 就是这里改的）。
  ///
  /// 入口：桌号下拉下面的那个小 chip（**所有外卖单**的当前单都显示：
  /// 有等待时间就写「等待 N 分钟」，没有就写「等待时间」）。
  Future<void> _editTakeawaySave(Order o) async {
    final pos = context.read<PosController>();
    final r = await showTakeawayNameDialog(context, o);
    if (r == null || !mounted) return;
    // 「不用名字」= 真的把名字清掉（跟点菜页「保存」弹窗一个口径）
    pos.setOrderLabel(o.id, r.label,
        waitMinutes: r.waitMinutes, clearName: true);
  }

  /// 点「已在单上」的某一行 → 回到点菜编辑框（选项 / 特别备注 / 份数）。
  Future<void> _editPlacedLine(String orderId, int index) async {
    final pos = context.read<PosController>();
    final order = pos.findOrder(orderId);
    if (order == null || index >= order.lines.length) return;
    final line = order.lines[index];

    // 「自定义」行：回它自己的框（金额 + 备注 —— 备注就是菜名）
    if (line.itemId == kCustomItemId) {
      final r = await showCustomItemDialog(
        context,
        initialNote: line.name,
        initialAmount: line.unitPrice,
      );
      if (r == null || !mounted) return;
      pos.updateCustomOrderLine(orderId, index, note: r.note, amount: r.amount);
      return;
    }

    final item = pos.menuItemForLine(line);

    final result = await showItemCustomizeDialog(
      context,
      item,
      title: line.name,
      initial: ItemEditResult(
        selections: line.options,
        notes: line.notes,
        // 已经有的备注**默认不变金额**：把原来的加价带回去
        notePrices: line.notePrices,
        quantity: line.quantity,
      ),
    );
    if (result == null || !mounted) return;
    pos.updateOrderLine(
      orderId,
      index,
      selections: result.selections,
      notes: result.notes,
      notePrices: result.notePrices,
      quantity: result.quantity,
    );
  }

  /// 「已在单上」的 ✕：先弹一次确认再删（防误触）。
  ///
  /// ⚠️ **最后一道菜也能删**：删掉它就等于**把整张单删掉**（跟「⋮ → 清空」一样），
  /// 所以确认框会换一句更重的话（`cart.deleteLastOrder`），点确认后连单带货一起清掉。
  Future<void> _deletePlacedLine(String orderId, int index) async {
    final pos = context.read<PosController>();
    final order = pos.findOrder(orderId);
    if (order == null || index >= order.lines.length) return;

    if (order.lines.length <= 1) {
      // 最后一道菜：整张单一起删
      if (!await _confirmDeleteOrder(order, lastLine: true)) return;
      if (!mounted) return;
      pos.clearOrderAndCart(orderId);
      return;
    }

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

  /// 「**整张单删掉**」的确认框：删最后一道菜、以及「⋮ → 清空」都走这里。
  ///
  /// [lastLine] = true 时标题换成更重的一句（"最后一道菜，删了整张单就没了"）。
  Future<bool> _confirmDeleteOrder(Order order, {bool lastLine = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          L10n.t(lastLine ? 'cart.deleteLastOrder' : 'cart.deleteOrder'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 把"是哪一张"写清楚（桌号 3  #12 / 外卖 张三 #3）
            Text(
              orderPlaceLabel(order),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t('cart.deleteOrderHint'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
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
    return ok == true;
  }

  /// 点「本次新增」的某一行 → 回到点菜编辑框，保存后替换这一行。
  Future<void> _editCartLine(CartItem item) async {
    final pos = context.read<PosController>();

    // 「自定义」行：回它自己的框（金额 + 备注 —— 备注就是菜名）
    if (item.menuItem.id == kCustomItemId) {
      final r = await showCustomItemDialog(
        context,
        initialNote: item.menuItem.name,
        initialAmount: item.menuItem.price,
      );
      if (r == null || !mounted) return;
      pos.updateCustomCartItem(item.key, note: r.note, amount: r.amount);
      return;
    }

    final result = await showItemCustomizeDialog(
      context,
      item.menuItem,
      initial: ItemEditResult(
        selections: item.selections,
        notes: item.notes,
        notePrices: item.notePrices,
        quantity: item.quantity,
      ),
    );
    if (result == null || !mounted) return;
    pos.updateCartItem(
      item.key,
      selections: result.selections,
      notes: result.notes,
      notePrices: result.notePrices,
      quantity: result.quantity,
    );
  }

  /// 分区小标题（「本次新增」）。
  ///
  /// **只留图标 + 名字**：件数（`N 件`）和「清空」按钮都搬走了
  /// （清空进了桌号旁边的「⋮」，件数看每一行的 `×N` 就够了）——
  /// 这一条压到最薄，把高度全让给菜。
  Widget _sectionHeader({
    required IconData icon,
    required String title,
  }) =>
      Container(
        color: const Color(0xFFF7F9F8),
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );

  /// 顶部：**桌号 / 外卖下拉**（堂食外卖出这里选）。
  ///
  /// 下拉里的顺序是固定的（改需求时别乱调）：
  /// **外卖**（开新单）→ **电话外卖**（开新单）→ **各桌**（有菜的橙色 +「已有 N」）
  /// → **进行中的外卖单**（外卖/电话外卖，**起没起名字都列**；没名字的用单号 `#3` 认）。
  ///
  /// 最后那一组就是"点完厨房还留在购物车里、随时能回去接着改 / 接着结账"的外卖单；
  /// 结账之后它不再是进行中 → 自然从列表里消失。
  Widget _targetSelector(PosController pos, Order? open) {
    final settings = context.watch<SettingsController>().settings;
    // 桌号按**自然顺序**排：数字在前（1,2,…,9,10），然后字母（A,B,C…SA,SB）
    // —— 设置里存的是什么顺序都不影响，这里只按名字排（见 utils/menu_sort.dart）
    final tables = sortedTables(settings.tables);
    // **进行中的外卖单**（外卖 + 电话外卖，有名字没名字都在）
    final takeaways = pos.openTakeawayOrders();
    // 正在编的是哪张外卖单：点过「保存 / 厨房」后它就是当前这张
    // （没起名字的外卖单没有桌号也没有名字，只能靠 id 认）
    final focused = pos.focusedOrder;
    String? focusedValue;
    for (final o in takeaways) {
      if (focused != null && o.id == focused.id) {
        focusedValue = '$_kSavedPrefix${o.id}';
      }
    }
    // ⚠️ 只在它**真的在列表里**时才当下拉的 value：否则 DropdownButton 会因为
    // "找不到对应的 item"直接抛断言（例如刚从订单页调出来的是一张**分单**——
    // 分单不出现在这个列表里，就退回按类型显示）
    final value = focusedValue ??
        (pos.isPhoneTakeaway
            ? _kPhoneTakeaway
            : pos.isTakeaway
                ? _kTakeaway
                : (tables.contains(pos.selectedTable) ? pos.selectedTable : null));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // （原来这里有一行「桌号」小标题，去掉了：下拉里每一项自己就写着「桌号 5 / 外卖」）
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  hint: Text(L10n.t('table.pickShort')),
                  items: [
                    // 外卖（= 开一张新单；后面的 #N 是它将要拿到的号）
                    DropdownMenuItem(
                      value: _kTakeaway,
                      child: _targetRow(
                        L10n.t('order.takeaway'),
                        color: const Color(0xFF37474F),
                        note: '#${pos.nextTakeawayNo}'
                            '${pos.openTakeawayCount > 0 ? ' · ${pos.openTakeawayCount} ${L10n.t('table.openOrders')}' : ''}',
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
                    // **进行中的外卖单**（点它回到那张单接着改 / 结账）。
                    // 名字和单号都在 `takeawayTag` 里：`张三 #3` / `#3`（没起名字）。
                    for (final o in takeaways)
                      DropdownMenuItem<String>(
                        value: '$_kSavedPrefix${o.id}',
                        child: _targetRow(
                          o.isPhoneTakeaway
                              ? L10n.t('order.phonecallTakeaway')
                              : L10n.t('order.takeaway'),
                          color: const Color(0xFF00838F),
                          name: o.takeawayTag.isEmpty ? null : o.takeawayTag,
                          note: '${o.itemCount} ${L10n.t('cart.items')}',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    if (v.startsWith(_kSavedPrefix)) {
                      // 进行中的外卖单：选中它 → 之后「保存 / 厨房 / 结账」都算这张单
                      final id = v.substring(_kSavedPrefix.length);
                      for (final o in takeaways) {
                        if (o.id == id) {
                          pos.focusOrder(o);
                          return;
                        }
                      }
                      return;
                    }
                    if (v == _kTakeaway) {
                      pos.selectTable('', takeaway: true);
                    } else if (v == _kPhoneTakeaway) {
                      // 电话外卖：不用桌号，跟外卖一样每单独立，只是标签/统计分开
                      pos.selectTable('',
                          takeaway: true,
                          type: OrderType.phonecallTakeaway);
                    } else {
                      pos.selectTable(v);
                    }
                  },
                ),
              ),
              // 桌号 / 外卖 旁边的「**⋮**」：移动单子 / 分单 / 清空
              _moreMenu(pos, open),
            ],
          ),
          // 外卖 / 电话外卖：**名字 + 等待时间**（点一下就改；等待时间会打在厨房单上）
          // 「保存」每次也会弹这个框，这个 chip 只是"不想保存也想改一下"时的快捷入口。
          if (open != null && open.isTakeaway) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16),
                label: Text(open.waitMinutes > 0
                    ? '${L10n.t('kitchen.wait')} ${open.waitMinutes} '
                        '${L10n.t('kitchen.minutes')}'
                    : L10n.t('takeaway.wait')),
                onPressed: () => _editTakeawaySave(open),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 桌号 / 外卖 下拉旁边那个「**⋮**」：用得少、但不该占地方的操作放这里。
  ///
  /// 三条：
  /// - **移动单子**（员工选错桌时用）→ 弹窗里左边挑单、右边挑桌；
  /// - **分单**（客人分开付钱）→ 去分单界面；
  /// - **清空** → **把这张桌/外卖的整张单删掉**（连购物车里没保存的菜一起清空）。
  ///   有单的时候就先弹一次确认（`cart.deleteOrder`），没单就只是清购物车。
  ///
  /// [open] 是当前这张进行中的单：没有单的时候「分单」是灰的（没东西可分）。
  Widget _moreMenu(PosController pos, Order? open) => PopupMenuButton<String>(
        tooltip: L10n.t('cart.more'),
        icon: const Icon(Icons.more_vert),
        onSelected: (v) async {
          switch (v) {
            case _kClearCart:
              // 有进行中的单 → 整张单删掉（先确认）；没有 → 只是清购物车
              if (open != null) {
                if (!await _confirmDeleteOrder(open)) return;
                if (!mounted) return;
                pos.clearOrderAndCart(open.id);
              } else {
                pos.clearCart();
              }
            case _kMoveOrder:
              // 当前这张是**分单**的话，默认选它的母单（分单要跟着母单一起挪）
              showMoveOrderDialog(
                context,
                orderId: open == null
                    ? ''
                    : (open.isSplit ? open.parentId : open.id),
              );
            case _kSplitBill:
              if (open != null) showSplitBillScreen(context, open.id);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: _kMoveOrder,
            // 一张进行中的单都没有 → 没东西可移
            enabled: pos.inProgressParents.isNotEmpty,
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 20),
                const SizedBox(width: 10),
                Text(L10n.t('cart.move')),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: _kSplitBill,
            // 这张桌/外卖单还没有进行中的单（或者是分单本身）→ 没东西可分
            enabled: open != null && !open.isSplit,
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 20),
                const SizedBox(width: 10),
                Text(L10n.t('cart.split')),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: _kClearCart,
            // 只要有单、或者购物车里有菜就能清 —— 已经保存/下过厨房的单也能这样删掉
            enabled: open != null || !pos.cartEmpty,
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 20),
                const SizedBox(width: 10),
                Text(L10n.t('cart.clear')),
              ],
            ),
          ),
        ],
      );

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

  /// 下拉里的一行：颜色圆点 + 名称 (+ 名字) (+ 备注)。
  ///
  /// [name] 是给"已保存的外卖单"用的：类型写「外卖」，名字写在后面强调一下
  /// （例：`外卖  张三 #3   2 件`）。
  Widget _targetRow(String label,
      {required Color color, String? note, String? name}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (name != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ] else
          const Spacer(),
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

/// 下拉里「已保存的外卖单」的前缀（后面接订单 id，见 `_targetSelector`）。
const String _kSavedPrefix = '__saved_takeaway__:';

/// 「⋮」菜单里「清空购物车」那一项的值（见 `_moreMenu`）。
const String _kClearCart = '__clear_cart__';

/// 「⋮」菜单里「移动单子」那一项的值。
const String _kMoveOrder = '__move_order__';

/// 「⋮」菜单里「分单」那一项的值。
const String _kSplitBill = '__split_bill__';

/// **已下厨**那一行的底色（浅绿）—— 只靠颜色区分，不写字、不占地方。
const Color _kSentBg = Color(0xFFF1F8F3);

/// **未下厨**（只是「保存」过）那一行的底色（浅黄）。
const Color _kUnsentBg = Color(0xFFFFF6E9);

/// 购物车里的一行（「已在单上」和「本次新增」**共用**）。
///
/// 版式（安卓小屏实测：以前那些标签 / 色条把菜名挤没了，所以只留最要紧的）：
/// ```
/// 牛肉炒饭                      ← 菜名（占整行 70% 以上，最多两行）
/// 换炒饭 +70                    ← 选项 / 备注（带价签，有才显示）
///                ¥98.00  ×1  ✕  ← 这一行的钱（含备注加价）+ 份数 + 删除
/// ```
///
/// **为什么要显示这一行的钱**：备注加价（「换炒饭 +70」）是算进这一行金额的，
/// 但以前行上只有 `×1`，看不出加价到底有没有生效 —— 现在金额就写在那儿，
/// 加没加钱一眼就知道（单价还是不显示，那一条仍然是"点这一行进框里看"）。
///
/// **不再写「已下厨 / 未下厨」那几个字**（太占地方），改成**底色**区分：
/// 已下厨 = 浅绿、还有份数没打给厨房 = 浅黄（[background]）。厨房单那边该打哪几份
/// 由 `OrderLine.unsentQty`（= 份数 − 厨房已收到几份）决定。
class _LineRow extends StatelessWidget {
  final String name;

  /// 选项 / 备注（空 = 不显示这一行）。
  final String detail;

  final int quantity;

  /// 这一行的金额（**含备注加价**，已经带货币符号）；空 = 不显示。
  final String amount;

  /// 这一行的底色（null = 白）。见 [_kSentBg] / [_kUnsentBg]。
  final Color? background;

  /// 点这一行 → 回点菜框改选项 / 备注 / 份数。
  final VoidCallback onTap;

  /// 行尾的 ✕。
  final VoidCallback onDelete;

  /// false 时 ✕ 是灰的（单上最后一道菜不让删）。
  final bool canDelete;

  const _LineRow({
    required this.name,
    required this.detail,
    required this.quantity,
    required this.onTap,
    required this.onDelete,
    this.amount = '',
    this.background,
    this.canDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // 底色：「已下厨」浅绿 / 「只是保存了」浅黄 —— 一眼分得清，又不占空间
      color: background ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              // 菜名 / 备注：`Expanded` 把剩下的宽度全给它（右边只有 份数 + ✕）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (detail.trim().isNotEmpty)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1FA85A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 这一行的钱（**含备注加价**）：加没加钱一眼看得出来
              if (amount.trim().isNotEmpty)
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              const SizedBox(width: 6),
              // 份数只**显示**成 `×2`（加减去掉了）：要改就点这一行，进去改数字
              _QtyText(quantity: quantity, color: const Color(0xFF1FA85A)),
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
}

/// 份数**只显示**（`×2`），不带加减按钮。
///
/// 为什么要这样：安卓小屏上「− 2 +」三个控件就把一行占掉小半，
/// 菜名被挤得只剩几个字。改份数的入口是**点这一行** → 点菜框里改数字。
class _QtyText extends StatelessWidget {
  final int quantity;
  final Color color;

  const _QtyText({required this.quantity, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.centerRight,
      child: Text(
        '×$quantity',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
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
