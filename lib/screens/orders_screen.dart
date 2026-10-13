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
// 进行中 / 已结单两种排法 + 已结单"只看某一天"的筛选
import '../utils/order_sort.dart';
import '../widgets/account_menu.dart';
import '../widgets/admin_gate.dart';
// 「已结单」点开：看明细 + 补打小票
import '../widgets/order_detail_dialog.dart';
import '../widgets/payment_flow.dart';
import 'daily_summary_screen.dart';

/// 订单页：分「进行中」和「已结单」两个标签页。
/// - 进行中：可点「结账」（折扣/税 + 收款 → 打顾客小票 → 转成已结单）；
///   一单一行：[桌号/名字] [金额大字] [餐品] [删除] [结账]。
/// - 已结单：**一天一天看**（跟「日结」一样的日期按钮，默认今天），两种排法
///   （按结账时间由近到远 / 按金额由大到小）；**点一张单**会打开明细，
///   可以核对、可以**补打小票**（不再有「结账」—— 钱早就收过了）；
///   删除**需要管理员权限**。
/// 「日结」按钮在这一页的**最右边**（也要管理员权限）。
///
/// 注：切到这一页时 `HomeShell` 会顺手同步一次（多设备一个单池，看到的就是最新的）。
class OrdersScreen extends StatefulWidget {
  /// **点一张「进行中」的单时要做的事**：调回「点单」页（`HomeShell` 传进来）。
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
    // 「进行中」按用户选的方式排：默认 = 外卖 → 电话外卖 → 桌子（桌号清单顺序）；
    // 另一种 = 最近保存 / 下厨房的在最上面（见 `utils/order_sort.dart`）
    final open = sortInProgressOrders(
      pos.inProgressOrders,
      OrderSort.fromId(settings.orderSort),
      settings.tables,
    );
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
            _OrderList(
              orders: open,
              inProgress: true,
              onOpenPos: widget.onOpenPos,
              header: const _InProgressSortBar(),
            ),
            _OrderList(
              orders: closed,
              inProgress: false,
              onOpenPos: widget.onOpenPos,
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

/// 两个列表共用的**小圆片**（排序 / 筛选用）。
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

/// 「进行中」列表上面那个排序开关：**按位置**（默认）/ **按时间**。
///
/// 选择存在设置里（`Settings.orderSort`），本机记住、不上云。
class _InProgressSortBar extends StatelessWidget {
  const _InProgressSortBar();

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<SettingsController>();
    final current = OrderSort.fromId(ctl.settings.orderSort);

    return _Bar(
      children: [
        _SortChip(
          selected: current == OrderSort.position,
          label: L10n.t('order.sort.position'),
          icon: Icons.table_restaurant_outlined,
          onTap: () => ctl.setOrderSort(OrderSort.position.id),
        ),
        _SortChip(
          selected: current == OrderSort.time,
          label: L10n.t('order.sort.time'),
          icon: Icons.schedule,
          onTap: () => ctl.setOrderSort(OrderSort.time.id),
        ),
      ],
    );
  }
}

/// 「已结单」列表上面那一条：**看哪一天** + 两种排法 + 右边的「日结」。
///
/// - 日期：点一下开日期选择器（**一天一天看**，跟日结一模一样），
///   挑过之后出现「今天」一键跳回今天；
/// - 排法：**按时间**（结账确认时间由近到远，默认）/ **按金额**（由大到小），
///   存在设置里（`Settings.closedSort`），本机记住、不上云；
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

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final bool inProgress;
  final VoidCallback? onOpenPos;

  /// 列表上面的东西（排序 / 日期筛选那条）。
  ///
  /// **一张单都没有时也留着**：筛了日期什么都没筛出来，得能改回来。
  final Widget? header;

  const _OrderList({
    required this.orders,
    required this.inProgress,
    this.onOpenPos,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final emptyText = inProgress
        ? L10n.t('cart.noOrders')
        : L10n.t('order.history.empty');

    return Column(
      children: [
        if (header != null) header!,
        Expanded(
          child: orders.isEmpty
              ? _EmptyOrders(text: emptyText)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  // 一条单只有一行了，间距也收紧一点 —— 一屏能放下更多张
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _OrderCard(
                    order: orders[i],
                    inProgress: inProgress,
                    onOpenPos: onOpenPos,
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final bool inProgress;
  final VoidCallback? onOpenPos;

  const _OrderCard({
    required this.order,
    required this.inProgress,
    this.onOpenPos,
  });

  /// 点这张**进行中**的单 → 调回「点单」页，购物车面板里就是它：
  /// 可以继续加菜、改份数、改备注、删菜，点「保存 / 厨房」都回到这张单上。
  void _openInPos(BuildContext context) {
    context.read<PosController>().focusOrder(order);
    onOpenPos?.call();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(L10n.t('order.tapToEdit')),
        duration: const Duration(milliseconds: 1400),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

    // 右边那点小字：**有才显示** —— 已结单显示支付方式。
    // 单号、时间、折扣税、外币明细**都不显示了** —— 一条单就是一行，一屏能扫很多张
    // （这些明细纸上（小票）和「日结」里都有）。
    final extras = inProgress ? '' : orderPaymentLabel(order);

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // **进行中**：点一下就调回「点单」页，购物车面板里就是它
        // （加菜 / 改份数 / 改备注 / 删菜）。
        // **已结单**：点开**明细**（可以核对、可以**补打小票**，没有"结账"）。
        onTap: inProgress
            ? () => _openInPos(context)
            : () => showClosedOrderDetail(context, order),
        child: Padding(
          // 一条单**只有一行**：上下各留 8（字放大了，留点余地）
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          // 只有中间那段「餐品」是弹性的（`Expanded`）：
          // 右边两粒按钮永远被推到**最右边**，不管菜名多长都一样。
          child: LayoutBuilder(builder: (context, box) {
            // 窗口宽（收银台 / 平板）才显示右边那些"有就有、没有也行"的小字；
            // 窄的时候（手机）先让位给桌号和菜名，免得把右边的按钮挤出去。
            final roomy = box.maxWidth >= 700;
            return Row(
              children: [
                // 桌号 / 名字 / 单号：**完整显示，不省略**（宽的时候能占 260）
                _placeTag(order, roomy ? 260 : 160),
                const SizedBox(width: 10),
                // **金额（大字）**：就在桌号 / 名字后面，一眼看到这一单多少钱
                // （金额也是**完整显示**的，绝不省略）
                Text(
                  money(order.total, settings.currencySymbol),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF232829),
                  ),
                ),
                const SizedBox(width: 12),
                // 餐品：**一行搞定**，太长就省略号（`…`）—— 它变形，按钮不变
                // （要看全就点开这张单：明细里一道菜一行）
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
                  // 给它一个**宽度上限**：内容再长也不会把右边的按钮挤出去
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
                // 还没推上后台的单：橙色小标记（一眼看出后台可能还没收到）
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
                // ---- 最右边：删除 + （进行中的）结账 ----
                // 这两粒**没有弹性**，所以永远贴着卡片右边缘。
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  tooltip: L10n.t('order.delete'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 22,
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                ),
                if (inProgress)
                  FilledButton(
                    onPressed: () => settleOrderFlow(context, order),
                    child: Text(L10n.t('order.settle')),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// 左边的标记：**桌号 / 外卖名字（含单号）**，电话外卖的等待时间也跟在这里面。
  ///
  /// ⚠️ 这里**绝对不省略**（你要求的）：桌号 / 名字 / 单号是"这单是谁的"，
  /// 省了就认不出单子（菜名反而可以省 —— 点开明细能看全）。
  /// 做法是**折行显示完整**，而不是打省略号：
  /// 宽度上限 260（窗口窄时 160），名字再长也只是多占一行。
  ///
  /// [maxWidth] 是它的宽度上限（窗口窄的时候收得更紧，但同样不省略）。
  Widget _placeTag(Order order, double maxWidth) {
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
                // 放不下就折行 —— **不打省略号**（内容必须看全）
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
