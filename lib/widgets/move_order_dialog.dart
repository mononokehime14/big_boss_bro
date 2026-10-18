import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
// 桌号 / 外卖名字 / 单号的统一写法（跟订单页一样）
import '../utils/order_label.dart';
import '../utils/menu_sort.dart';

/// **移动单子**窗口：左边挑一张进行中的单，右边挑要挪到哪张桌，下面按「确认」。
///
/// 用在员工**选错桌**的时候（实际是 3 号桌，却点成了 5 号桌）。
///
/// 规则（见 `PosController.moveOrderToTable`）：
/// - 目标桌空着 → 直接把单挪过去；
/// - 目标桌已经有单 → **把菜并进那张单**，然后删掉原来那张
///   （一张桌只留一张单，不然桌号下拉会认错）；
/// - 这张单的分单跟着一起换桌。
Future<void> showMoveOrderDialog(BuildContext context, {String? orderId}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MoveOrderDialog(initialOrderId: orderId ?? ''),
    );

class _MoveOrderDialog extends StatefulWidget {
  /// 默认选中的单（从购物车「⋮」进来时，就是当前那张单的 id）。
  final String initialOrderId;

  const _MoveOrderDialog({required this.initialOrderId});

  @override
  State<_MoveOrderDialog> createState() => _MoveOrderDialogState();
}

class _MoveOrderDialogState extends State<_MoveOrderDialog> {
  /// 选中的源单 id（空 = 还没选）。
  String _orderId = '';

  /// 选中的目标桌（空 = 还没选，会自动挑第一个能用的）。
  String _table = '';

  @override
  void initState() {
    super.initState();
    _orderId = widget.initialOrderId;
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final symbol = settings.currencySymbol;

    // 左边：进行中的**母单**（分单不在这里 —— 它们跟着母单走）
    final orders = pos.inProgressParents;
    Order? source;
    for (final o in orders) {
      if (o.id == _orderId) {
        source = o;
        break;
      }
    }
    // 右边：所有桌号（自然顺序，跟点单页一样）
    final tables = sortedTables(settings.tables);

    // 还没挑目标桌（或者挑的那张已经被删掉）→ 默认用第一个**跟源单不一样**的桌
    var table = _table;
    if (table.isEmpty || !tables.contains(table)) {
      for (final t in tables) {
        if (source == null || source.isTakeaway || t != source.table) {
          table = t;
          break;
        }
      }
      if (table.isEmpty && tables.isNotEmpty) table = tables.first;
    }

    final sameTable =
        source != null && !source.isTakeaway && source.table == table;
    final canMove = source != null && table.isNotEmpty && !sameTable;
    // 确认按钮里要用到它（这里先抓成非空，免得回调里再判一次）
    final src = canMove ? source : null;

    // 小屏（手机）别撑爆弹窗：宽 / 高都跟屏幕走，取一个不超过它的值
    final size = MediaQuery.of(context).size;
    final width = math.min(640.0, size.width * 0.86);
    final height = math.min(420.0, size.height * 0.62);

    // 左栏：当前单子
    final left = _Pane(
      title: L10n.t('move.source'),
      child: ListView(
        children: [
          for (final o in orders)
            _OrderTile(
              order: o,
              selected: o.id == (source?.id ?? ''),
              trailing: money(o.total, symbol),
              onTap: () => setState(() => _orderId = o.id),
            ),
        ],
      ),
    );
    // 右栏：要移动到的桌
    final right = _Pane(
      title: L10n.t('move.target'),
      child: ListView(
        children: [
          for (final t in tables)
            _TableTile(
              table: t,
              selected: t == table,
              // 那桌已经有菜 → 提示「已有 N」（确认后会并单）
              note: pos.openItemCountForTable(t) > 0
                  ? '${L10n.t('move.occupied')} ${pos.openItemCountForTable(t)}'
                  : null,
              onTap: () => setState(() => _table = t),
            ),
        ],
      ),
    );

    return AlertDialog(
      title: Text(L10n.t('move.title')),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: width,
        height: height,
        child: orders.isEmpty
            ? Center(
                child: Text(
                  L10n.t('move.emptySource'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            // 宽屏：左右两栏；窄屏（手机竖着）：上下两栏
            : (width < 430
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: left),
                      const Divider(height: 1),
                      Expanded(child: right),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: left),
                      const VerticalDivider(width: 1),
                      Expanded(child: right),
                    ],
                  )),
      ),
      actions: [
        if (sameTable)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              L10n.t('move.same'),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFFEF6C00)),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: src == null
              ? null
              : () {
                  final merged = pos.moveOrderToTable(src.id, table);
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  if (merged == null) return;
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(
                      content: Text(
                        // 换了张单（id 变了）= 并进目标桌那张了
                        merged.id != src.id
                            ? L10n.t('move.merged')
                            : L10n.t('move.done'),
                      ),
                      duration: const Duration(milliseconds: 1600),
                    ));
                },
          child: Text(L10n.t('common.ok')),
        ),
      ],
    );
  }
}

/// 左右两栏共用的外壳：上面一个标题，下面滚动列表。
class _Pane extends StatelessWidget {
  final String title;
  final Widget child;

  const _Pane({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// 左边那一行：一张进行中的单（标签 + 件数 + 金额）。
class _OrderTile extends StatelessWidget {
  final Order order;
  final bool selected;
  final String trailing;
  final VoidCallback onTap;

  const _OrderTile({
    required this.order,
    required this.selected,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xFF1FA85A).withValues(alpha: 0.12),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? const Color(0xFF1FA85A) : Colors.grey,
      ),
      title: Text(
        orderPlaceLabel(order),
        maxLines: 2,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${order.itemCount} ${L10n.t('cart.items')}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Text(
        trailing,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );
  }
}

/// 右边那一行：一个桌号（有菜就提示「已有 N」）。
class _TableTile extends StatelessWidget {
  final String table;
  final bool selected;
  final String? note;
  final VoidCallback onTap;

  const _TableTile({
    required this.table,
    required this.selected,
    required this.onTap,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xFF1FA85A).withValues(alpha: 0.12),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? const Color(0xFF1FA85A) : Colors.grey,
      ),
      title: Text(
        '${L10n.t('order.table')} $table',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      trailing: note == null
          ? null
          : Text(
              note!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF6C00),
              ),
            ),
      onTap: onTap,
    );
  }
}
