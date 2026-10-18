import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../services/sync_service.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
// 顶栏同步按钮里的「上次同步」时间（`timeShort`）
import '../utils/format.dart';
// 桌号 / 外卖标签、支付方式文字（跟「日结」明细共用同一份写法）
import '../utils/order_label.dart';
// 已结单的「按什么排」+「只看某一天」；进行中是固定按单号从小到大
import '../utils/order_sort.dart';
import '../utils/pricing.dart';
import '../widgets/account_menu.dart';
import '../widgets/admin_gate.dart';
// 「已结单」点开：看明细 + 补打小票
import '../widgets/order_detail_dialog.dart';
import '../widgets/payment_flow.dart';
import 'daily_summary_screen.dart';

/// 订单页：分「进行中」和「已结单」两个标签页。
///
/// **进行中**（改版后）：
/// - 上面三个按钮：**外卖 / 电话外卖 / 堂食**（默认堂食）—— 只看那一类；
///   以前那三个排序按钮删掉了（实际没用），**永远按单号从小到大**排；
/// - 界面**一分为二**：**左边是单子列表**（桌号/名字 + 金额 + 删除 + 编辑 + 结账），
///   **右边是选中那张单的菜品明细 + 合计**；
/// - **点单子 = 在右边看明细**（不再跳去点单页）；
///   要点菜 / 改单就点那一行的**编辑**按钮 → 跳到点单页、并把这张单调进购物车。
///
/// **已结单**：**一天一天看**（跟「日结」一样的日期按钮，默认今天），三种排法；
/// 点一张单打开明细，可以核对、可以**补打小票**；删除需要管理员权限。
/// 「日结」按钮在这一页的**最右边**（也要管理员权限）。
///
/// 注：切到这一页时 `HomeShell` 会顺手同步一次（多设备一个单池，看到的就是最新的）。
class OrdersScreen extends StatefulWidget {
  /// **点「编辑」时要做的事**：调回「点单」页（`HomeShell` 传进来）。
  ///
  /// 真正的"把这张单调出来"由 `PosController.focusOrder` 完成，这里只负责切标签页。
  final VoidCallback? onOpenPos;

  const OrdersScreen({super.key, this.onOpenPos});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  /// 「已结单」看的是**哪一天**（`yyyy-MM-dd`）；null = 跟着「今天」走。
  ///
  /// 跟「日结」一个路子：默认就是今天，**开着过零点会自动跟到新的一天**；
  /// 手动挑过某一天之后就停在那天（那条里会出现「今天」一键跳回来）。
  String? _pickedDay;

  /// 今天（每次 build 重算，所以过零点不用手动刷新）。
  String get _todayKey => PosController.dateKey(DateTime.now());

  /// 挑一天看（跟日结一样：**一天一天看**，不做时间段）。
  Future<void> _pickDay() async {
    final parts = (_pickedDay ?? _todayKey).split('-');
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        int.tryParse(parts[0]) ?? DateTime.now().year,
        int.tryParse(parts[1]) ?? 1,
        int.tryParse(parts[2]) ?? 1,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _pickedDay = PosController.dateKey(picked));
  }

  /// 打开「日结」（**要管理员权限**）。
  ///
  /// 按钮在「已结单」那一页的**最右边**：看的都是"某一天的账"，放一起顺手
  /// （日结就是这一天那几个数字的汇总）。
  /// 打开时**带上正在看的那一天**（`initialDayKey`），不然会"看着 10/3 的单子、
  /// 点开日结却是今天的数字"。
  Future<void> _openSummary(String day) async {
    final ok = await requireAdmin(
      context,
      reason: L10n.t('auth.summaryNeeded'),
    );
    if (!ok || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailySummaryScreen(initialDayKey: day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    // 「进行中」：全部（按类型筛选在 _InProgressTab 里做，因为它要记住选的是哪一类）
    final open = pos.inProgressOrders;
    // 「已结单」：只看**这一天**（跟「日结」同一套"哪一天"），再按选的排法排
    final day = _pickedDay ?? _todayKey;
    final closed = sortClosedOrders(
      filterOrdersOnDate(pos.completedOrders, day),
      ClosedSort.fromId(settings.closedSort),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t('order.history.title')),
          actions: [
            // 后台同步状态：待上传几张 + 点一下立刻同步
            const _SyncButton(),
            const AccountMenuButton(),
          ],
          bottom: TabBar(
            tabs: [
              // 括号里是**当前筛出来的张数**（已结单选了某天就是那天的张数）
              Tab(text: '${L10n.t('order.status.inProgress')} (${open.length})'),
              Tab(text:
                  '${L10n.t('order.status.completed')} (${closed.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InProgressTab(orders: open, onOpenPos: widget.onOpenPos),
            _ClosedList(
              orders: closed,
              header: _ClosedFilterBar(
                day: day,
                today: _todayKey,
                onPickDay: _pickDay,
                onToday: () => setState(() => _pickedDay = null),
                onOpenSummary: () => _openSummary(day),
                count: closed.length,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **「进行中」这一页**：上面是类型筛选，下面**左列表 / 右明细**。
///
/// 选中的单子存在这里（`_selectedId`）：切类型、单子被结掉之后会自动落到第一张上。
class _InProgressTab extends StatefulWidget {
  /// 全部「进行中」的单（不筛类型 —— 筛选在这里做）。
  final List<Order> orders;

  /// 点「编辑」：切回点单页。
  final VoidCallback? onOpenPos;

  const _InProgressTab({required this.orders, this.onOpenPos});

  @override
  State<_InProgressTab> createState() => _InProgressTabState();
}

class _InProgressTabState extends State<_InProgressTab> {
  /// 看哪一类（默认**堂食**）。
  OrderType _type = OrderType.dineIn;

  /// 左边选中的那张单（空 = 没选，会自动落到第一张）。
  String _selectedId = '';

  /// 点「编辑」：把这张单调进点单页的购物车。
  void _edit(Order order) {
    context.read<PosController>().focusOrder(order);
    widget.onOpenPos?.call();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(L10n.t('order.editHint')),
        duration: const Duration(milliseconds: 1600),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final symbol = settings.currencySymbol;

    // 只看选中的那一类；**永远按单号从小到大**（排序开关已经去掉）
    final list = sortOpenOrdersByNumber(
      widget.orders.where((o) => o.orderType == _type).toList(),
    );

    // 选中的那张不在这个列表里（切了类型 / 刚被结账 / 被删）→ 先显示第一张
    Order? selected;
    for (final o in list) {
      if (o.id == _selectedId) {
        selected = o;
        break;
      }
    }
    selected ??= list.isEmpty ? null : list.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- 上面：外卖 / 电话外卖 / 堂食 ----
        _Bar(
          children: [
            _SortChip(
              selected: _type == OrderType.takeaway,
              label: L10n.t('order.takeaway'),
              icon: Icons.shopping_bag_outlined,
              onTap: () => setState(() => _type = OrderType.takeaway),
            ),
            _SortChip(
              selected: _type == OrderType.phonecallTakeaway,
              label: L10n.t('order.phonecallTakeaway'),
              icon: Icons.phone_in_talk_outlined,
              onTap: () => setState(() => _type = OrderType.phonecallTakeaway),
            ),
            _SortChip(
              selected: _type == OrderType.dineIn,
              label: L10n.t('order.dineIn'),
              icon: Icons.table_restaurant_outlined,
              onTap: () => setState(() => _type = OrderType.dineIn),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // 宽屏：左右两栏；窄屏（手机）：上下两栏
              final wide = box.maxWidth >= 760;
              final left = _openList(list, selected, symbol);
              final right = _OrderLinesPane(order: selected, symbol: symbol);
              if (wide) {
                return Row(
                  children: [
                    Expanded(flex: 5, child: left),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 4, child: right),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(flex: 5, child: left),
                  const Divider(height: 1),
                  Expanded(flex: 4, child: right),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 左边：单子列表（一行 = 桌号/名字 + 金额 + 删除 + 编辑 + 结账）。
  Widget _openList(List<Order> list, Order? selected, String symbol) {
    if (list.isEmpty) return _EmptyOrders(text: L10n.t('cart.noOrders'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _OpenOrderRow(
        order: list[i],
        symbol: symbol,
        selected: list[i].id == selected?.id,
        onTap: () => setState(() => _selectedId = list[i].id),
        onEdit: () => _edit(list[i]),
      ),
    );
  }
}

/// **进行中的一行**：左边桌号/名字，右边金额 + 删除 + 编辑 + 结账。
///
/// 点这一行 = **在右边看明细**（不跳页）；要改单就点「编辑」。
class _OpenOrderRow extends StatelessWidget {
  final Order order;
  final String symbol;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _OpenOrderRow({
    required this.order,
    required this.symbol,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF1FA85A);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      clipBehavior: Clip.antiAlias,
      color: selected ? const Color(0xFFEDF7F1) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? accent : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: LayoutBuilder(builder: (context, box) {
            // 名字/单号最多占一半，右边那一组永远贴着右边缘（金额一列对齐）。
            // 左边用 `Expanded` 包住：屏幕很窄时它自己换行，不会把右边挤出去。
            final tagWidth = box.maxWidth * 0.5;
            return Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PlaceTag(order: order, maxWidth: tagWidth),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  money(order.total, symbol),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF232829),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  tooltip: L10n.t('order.delete'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: L10n.t('order.edit'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF1565C0)),
                ),
                FilledButton(
                  onPressed: () => settleOrderFlow(context, order),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(L10n.t('order.settle')),
                ),
              ],
            );
          }),
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
}

/// 右边：选中那张单的**菜品明细 + 合计**（样式跟结账窗口左边那份一样）。
class _OrderLinesPane extends StatelessWidget {
  final Order? order;
  final String symbol;

  const _OrderLinesPane({required this.order, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long, size: 44, color: Colors.grey),
              const SizedBox(height: 10),
              Text(
                L10n.t('order.pickHint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final price = PriceBreakdown.of(
      subtotal: o.subtotal,
      discountType: o.discountType,
      discountValue: o.discountValue,
      taxRate: o.taxRate,
      taxIncluded: o.taxIncluded,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- 标题：哪张单 + 几件 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  orderPlaceLabel(o),
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${o.itemCount}${L10n.t('cart.items')}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ---- 菜品明细 ----
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: o.lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _lineTile(o.lines[i]),
          ),
        ),
        // ---- 底部：小计 / 折扣 / 税 / 合计 ----
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _breakdown(o, price),
        ),
      ],
    );
  }

  /// 明细里的一道菜（只读）：菜名 + 数量×单价 · 选项 · 备注 + 金额。
  Widget _lineTile(OrderLine l) {
    final detail = <String>[
      '${l.quantity} × ${money(l.effectiveUnitPrice, symbol)}'
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
                  // 这页是**给收银员看的**：跟点单页一样显示昵称
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

  /// 金额明细（小计 / 折扣 / 税 / 合计）。
  Widget _breakdown(Order o, PriceBreakdown price) {
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
              L10n.t('receipt.labelDiscount'),
              '-${money(price.discount, symbol)}',
              color: const Color(0xFFEF6C00),
            ),
          if (price.tax != 0)
            _row(
              '${L10n.t('receipt.labelTax')}'
              '${o.taxRate == 0 ? '' : ' ${o.taxRate.toStringAsFixed(0)}%'}'
              '${o.taxIncluded ? ' (${L10n.t('tax.included')})' : ''}',
              money(price.tax, symbol),
            ),
          const Divider(height: 12),
          _row(L10n.t('receipt.labelTotal'), money(price.total, symbol),
              bold: true, big: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {Color? color, bool bold = false, bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: big ? 16 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: color ?? const Color(0xFF232829),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: big ? 22 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? const Color(0xFF232829),
            ),
          ),
        ],
      ),
    );
  }
}

/// 两个列表共用的**小圆片**（类型筛选 / 已结单的排序用）。
///
/// 选中就是绿底白字，没选中是灰字 —— 一眼看出现在是哪一种。
class _SortChip extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SortChip({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: const Color(0xFF1FA85A),
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? Colors.white : Colors.grey.shade600,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF232829),
        ),
      ),
    );
  }
}

/// 「已结单」列表上面那一条：**看哪一天** + 三种排法 + 右边的「日结」。
///
/// - 日期：点一下开日期选择器（**一天一天看**，跟日结一模一样），
///   挑过之后出现「今天」一键跳回今天；
/// - 排法：**默认（按单号，从大到小）** / **按时间**（结账确认时间由近到远）/
///   **按金额**（由大到小），存在设置里（`Settings.closedSort`），本机记住、不上云；
/// - 最右边：「日结」按钮（**要管理员权限**）。
class _ClosedFilterBar extends StatelessWidget {
  /// 当前看的是哪一天。
  final String day;

  /// 今天（跟 [day] 一样就不用显示「今天」那个按钮）。
  final String today;

  final VoidCallback onPickDay;
  final VoidCallback onToday;
  final VoidCallback onOpenSummary;

  /// 这一天有几张单（跟在后面显示，方便核对）。
  final int count;

  const _ClosedFilterBar({
    required this.day,
    required this.today,
    required this.onPickDay,
    required this.onToday,
    required this.onOpenSummary,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<SettingsController>();
    final current = ClosedSort.fromId(ctl.settings.closedSort);

    return _Bar(
      // 最右边：日结（哪一天的账，跟这一页看的正是同一天）
      trailing: TextButton.icon(
        onPressed: onOpenSummary,
        icon: const Icon(Icons.summarize_outlined, size: 18),
        label: Text(L10n.t('summary.title')),
      ),
      children: [
        Tooltip(
          message: L10n.t('summary.date'),
          child: OutlinedButton.icon(
            onPressed: onPickDay,
            icon: const Icon(Icons.calendar_today, size: 18),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: const Color(0xFF1FA85A),
              side: const BorderSide(color: Color(0xFF1FA85A)),
            ),
            label: Text(day, style: const TextStyle(fontSize: 14)),
          ),
        ),
        // 看的是过去某一天 → 给一个一键回到今天
        if (day != today)
          ActionChip(
            onPressed: onToday,
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.today, size: 18, color: Color(0xFF1FA85A)),
            label: Text(L10n.t('order.date.today'),
                style: const TextStyle(fontSize: 14)),
          ),
        _SortChip(
          selected: current == ClosedSort.number,
          label: L10n.t('order.sort.number'),
          icon: Icons.tag,
          onTap: () => ctl.setClosedSort(ClosedSort.number.id),
        ),
        _SortChip(
          selected: current == ClosedSort.time,
          label: L10n.t('order.sort.time'),
          icon: Icons.schedule,
          onTap: () => ctl.setClosedSort(ClosedSort.time.id),
        ),
        _SortChip(
          selected: current == ClosedSort.amount,
          label: L10n.t('order.sort.amount'),
          icon: Icons.payments_outlined,
          onTap: () => ctl.setClosedSort(ClosedSort.amount.id),
        ),
        Text(
          '${L10n.t('summary.orders')} $count',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// 列表上面那一条的**统一外壳**：用 `Wrap` 排，窗口窄了自己换行，不会溢出。
///
/// [trailing] 给了就放在**最右边**（「已结单」那页的日结按钮）。
class _Bar extends StatelessWidget {
  final List<Widget> children;
  final Widget? trailing;

  const _Bar({required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final left = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: trailing == null
          ? left
          : Row(
              children: [
                Expanded(child: left),
                const SizedBox(width: 8),
                trailing!,
              ],
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

/// **「已结单」列表**：只有一列，点一张单 → 明细窗口（可补打小票）。
class _ClosedList extends StatelessWidget {
  final List<Order> orders;

  /// 列表上面的东西（日期筛选 + 排序那条）。**一张单都没有时也留着**。
  final Widget? header;

  const _ClosedList({required this.orders, this.header});

  @override
  Widget build(BuildContext context) {
    return Column(
      // ⚠️ 必须 `stretch`：排序 / 筛选那一条里面是 `Wrap`（会收缩到内容宽度），
      // 不拉伸的话会被 Column 默认的 `center` 摆到**中间**去。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) header!,
        Expanded(
          child: orders.isEmpty
              ? _EmptyOrders(text: L10n.t('order.history.empty'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) =>
                      _ClosedOrderCard(order: orders[i]),
                ),
        ),
      ],
    );
  }
}

/// 「已结单」的一行：点开看明细 + 补打小票；删除要管理员权限。
class _ClosedOrderCard extends StatelessWidget {
  final Order order;

  const _ClosedOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    // 右边那点小字：**有才显示** —— 已结单显示支付方式。
    final extras = orderPaymentLabel(order);

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showClosedOrderDetail(context, order),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: LayoutBuilder(builder: (context, box) {
            // 窗口宽（收银台 / 平板）才显示右边那些"有就有、没有也行"的小字；
            // 窄的时候（手机）先让位给桌号和菜名，免得把右边的按钮挤出去。
            final roomy = box.maxWidth >= 700;
            final tagWidth = box.maxWidth * 0.5;
            return Row(
              children: [
                _PlaceTag(order: order, maxWidth: tagWidth),
                const SizedBox(width: 12),
                // 餐品：**一行搞定**，太长就省略号
                Expanded(
                  child: Text(
                    order.lines.map((l) => '${l.name}×${l.quantity}').join('，'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                  ),
                ),
                if (roomy && extras.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      extras,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                ],
                // 还没推上后台的单：橙色小标记
                if (roomy && order.dirty && settings.syncEnabled) ...[
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
                const SizedBox(width: 12),
                Text(
                  money(order.total, settings.currencySymbol),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF232829),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  tooltip: L10n.t('order.delete'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 22,
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                ),
              ],
            );
          }),
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
}

/// 左边的标记：**桌号 / 外卖名字（含单号）**，电话外卖的等待时间也跟在这里面。
///
/// ⚠️ 这里**绝对不省略**（你要求的）：桌号 / 名字 / 单号是"这单是谁的"，
/// 省了就认不出单子。做法是**折行显示完整**，而不是打省略号。
class _PlaceTag extends StatelessWidget {
  final Order order;

  /// 宽度上限（调用方给的是**整行宽度的一半**）。
  final double maxWidth;

  const _PlaceTag({required this.order, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final wait = order.waitMinutes;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1FA85A).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                orderPlaceLabel(order),
                softWrap: true,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1FA85A),
                ),
              ),
            ),
            if (wait > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$wait ${L10n.t('kitchen.minutes')}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFEF6C00),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
