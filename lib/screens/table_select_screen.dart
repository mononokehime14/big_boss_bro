import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/menu_sort.dart';
import '../utils/order_label.dart';
import '../widgets/account_menu.dart';

/// 点单前的**选桌 / 选外卖**页面。
///
/// 顺序固定：
/// 1. **开新单**：外卖 / 电话外卖 / 平台外卖；
/// 2. **堂食桌号**：有进行中单的橙色、空桌绿色（跟点餐页下拉同一个颜色）；
/// 3. **进行中的外卖单**：有名字显示名字 + 单号，没名字显示单号；青色。
///
/// 点任意一格 → 选中目标 → 回调 [onSelected]，进入原来的点单界面。
class TableSelectScreen extends StatelessWidget {
  /// 选好桌 / 外卖之后调用（`PosScreen` 用它切到点单界面）。
  final VoidCallback onSelected;

  const TableSelectScreen({super.key, required this.onSelected});

  static const Color _takeawayColor = Color(0xFF37474F);
  static const Color _phoneColor = Color(0xFF6A1B9A);
  static const Color _platformColor = Color(0xFF00695C);
  static const Color _tableOccupied = Color(0xFFEF6C00);
  static const Color _tableEmpty = Color(0xFF2E7D32);
  static const Color _openTakeaway = Color(0xFF00838F);

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final tables = sortedTables(settings.tables);
    final openTakeaways = pos.openTakeawayOrders();

    final name = settings.storeName.trim();
    final title = name.isEmpty
        ? L10n.t('pos.chooseTarget')
        : '$name · ${L10n.t('pos.chooseTarget')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: const [AccountMenuButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---- 1) 开新单：外卖 / 电话外卖 / 平台外卖 ----
          _sectionHeader(Icons.add_circle_outline, L10n.t('pos.newOrder')),
          _grid([
            _PickTile(
              title: L10n.t('order.takeaway'),
              subtitle: '#${pos.nextTakeawayNo}'
                  '${pos.openTakeawayCount > 0 ? ' · ${pos.openTakeawayCount} ${L10n.t('table.openOrders')}' : ''}',
              icon: Icons.shopping_bag_outlined,
              color: _takeawayColor,
              onTap: () {
                pos.selectTable('', takeaway: true);
                onSelected();
              },
            ),
            _PickTile(
              title: L10n.t('order.phonecallTakeaway'),
              subtitle: pos.openPhoneTakeawayCount > 0
                  ? '${pos.openPhoneTakeawayCount} ${L10n.t('table.openOrders')}'
                  : null,
              icon: Icons.phone_in_talk_outlined,
              color: _phoneColor,
              onTap: () {
                pos.selectTable('',
                    takeaway: true, type: OrderType.phonecallTakeaway);
                onSelected();
              },
            ),
            _PickTile(
              title: L10n.t('order.platformTakeaway'),
              subtitle: pos.openPlatformTakeawayCount > 0
                  ? '${pos.openPlatformTakeawayCount} ${L10n.t('table.openOrders')}'
                  : null,
              icon: Icons.delivery_dining_outlined,
              color: _platformColor,
              onTap: () {
                pos.selectTable('',
                    takeaway: true, type: OrderType.platformTakeaway);
                onSelected();
              },
            ),
          ]),

          // ---- 2) 堂食桌号（有单 = 橙，空桌 = 绿）----
          if (tables.isNotEmpty) ...[
            _sectionHeader(
                Icons.table_restaurant_outlined, L10n.t('pos.dineInTables')),
            _grid([
              for (final t in tables)
                _PickTile(
                  title: '${L10n.t('order.table')} $t',
                  subtitle: pos.openItemCountForTable(t) > 0
                      ? '${L10n.t('table.already')} ${pos.openItemCountForTable(t)}'
                      : L10n.t('table.empty'),
                  icon: Icons.table_restaurant_outlined,
                  color: pos.openItemCountForTable(t) > 0
                      ? _tableOccupied
                      : _tableEmpty,
                  onTap: () {
                    pos.selectTable(t);
                    onSelected();
                  },
                ),
            ]),
          ],

          // ---- 3) 进行中的外卖单（有名字写名字，没名字写单号）----
          if (openTakeaways.isNotEmpty) ...[
            _sectionHeader(
                Icons.receipt_long_outlined, L10n.t('pos.openTakeaway')),
            _grid([
              for (final o in openTakeaways)
                _PickTile(
                  // 有名字就把名字 + 单号放在最显眼的位置；没名字就是 `#号`
                  title: o.takeawayTag.isEmpty
                      ? orderTypeLabel(o.orderType)
                      : o.takeawayTag,
                  subtitle:
                      '${orderTypeLabel(o.orderType)} · ${o.itemCount} ${L10n.t('cart.items')}',
                  icon: _typeIcon(o.orderType),
                  color: _openTakeaway,
                  onTap: () {
                    // 用 id 钉住这张单：没起名字的外卖单也能准确调出来
                    pos.focusOrder(o);
                    onSelected();
                  },
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _grid(List<Widget> tiles) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 104,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (_, i) => tiles[i],
      );

  static IconData _typeIcon(OrderType type) {
    switch (type) {
      case OrderType.dineIn:
        return Icons.table_restaurant_outlined;
      case OrderType.takeaway:
        return Icons.shopping_bag_outlined;
      case OrderType.phonecallTakeaway:
        return Icons.phone_in_talk_outlined;
      case OrderType.platformTakeaway:
        return Icons.delivery_dining_outlined;
    }
  }
}

/// 选桌页的一格：图标 + 名称 + 小字（空桌 / 已有 N / 单号…）。
///
/// 颜色跟点餐页下拉完全一致：有单的桌橙、空桌绿、进行中的外卖青。
class _PickTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PickTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
