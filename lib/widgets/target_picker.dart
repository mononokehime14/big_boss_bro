import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/menu_sort.dart';
import '../utils/order_label.dart';

/// 点「保存 / 厨房 / 结账」时**还没选桌 / 外卖** → 弹出这个列表让用户先选。
///
/// 列表顺序和购物车顶部的下拉完全一致：
/// 1. 开新单：外卖 / 电话外卖 / 平台外卖；
/// 2. 堂食桌号（有进行中单 = 橙色，空桌 = 绿色）；
/// 3. 进行中的外卖单（有名字显示名字 + 单号，没名字显示 `#号`）。
///
/// **不包含“未选择”这一项** —— 用户必须选一个真实目标才能继续。
/// 选完返回 true，调用方（`_submitOrder`）会接着执行刚才按下的保存 / 厨房 / 结账。
Future<bool> showTargetPicker(BuildContext context) async {
  final pos = context.read<PosController>();
  final settings = context.read<SettingsController>().settings;
  final tables = sortedTables(settings.tables);
  final takeaways = pos.openTakeawayOrders();

  // 分单也列出来（缩进挂在母单下面）：没有它的话，从"未选择"状态直接保存
  // 会先选到母单，想加到某张分单上就没机会了。
  final tableSplits = <String, List<Order>>{};
  final listedSplits = <String>{};
  for (final t in tables) {
    final p = pos.openParentForTable(t);
    if (p == null) continue;
    final splits =
        pos.splitsOf(p.id).where((s) => s.isInProgress).toList();
    tableSplits[t] = splits;
    for (final s in splits) {
      listedSplits.add(s.id);
    }
  }
  final takeawaySplits = <String, List<Order>>{};
  for (final o in takeaways) {
    final splits =
        pos.splitsOf(o.id).where((s) => s.isInProgress).toList();
    takeawaySplits[o.id] = splits;
    for (final s in splits) {
      listedSplits.add(s.id);
    }
  }
  // 母单已结账 / 桌号不在设置里，但分单还没结：兜底放最后。
  final looseSplits = pos.openSplitOrders
      .where((s) => !listedSplits.contains(s.id))
      .toList()
    ..sort((a, b) => a.splitNo.compareTo(b.splitNo));

  final size = MediaQuery.sizeOf(context);
  final width = math.min(460.0, size.width * 0.9);
  final height = math.min(520.0, size.height * 0.7);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      void pick(VoidCallback apply) {
        apply();
        Navigator.of(dialogContext).pop(true);
      }

      Widget splitTile(Order s) => _PickerTile(
            title: orderPlaceLabel(s),
            subtitle: '${s.itemCount} ${L10n.t('cart.items')}',
            color: const Color(0xFF1565C0),
            indent: true,
            onTap: () => pick(() => pos.focusOrder(s)),
          );

      return AlertDialog(
        title: Text(
          L10n.t('table.pickShort'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: width,
          height: height,
          child: ListView(
            shrinkWrap: true,
            children: [
              // ---- 1) 开新单：外卖 / 电话外卖 / 平台外卖 ----
              _PickerTile(
                title: L10n.t('order.takeaway'),
                subtitle: '#${pos.nextTakeawayNo}'
                    '${pos.openTakeawayCount > 0 ? ' · ${pos.openTakeawayCount} ${L10n.t('table.openOrders')}' : ''}',
                color: const Color(0xFF37474F),
                onTap: () => pick(() => pos.selectTable('', takeaway: true)),
              ),
              _PickerTile(
                title: L10n.t('order.phonecallTakeaway'),
                subtitle: pos.openPhoneTakeawayCount > 0
                    ? '${pos.openPhoneTakeawayCount} ${L10n.t('table.openOrders')}'
                    : null,
                color: const Color(0xFF6A1B9A),
                onTap: () => pick(() => pos.selectTable('',
                    takeaway: true, type: OrderType.phonecallTakeaway)),
              ),
              _PickerTile(
                title: L10n.t('order.platformTakeaway'),
                subtitle: pos.openPlatformTakeawayCount > 0
                    ? '${pos.openPlatformTakeawayCount} ${L10n.t('table.openOrders')}'
                    : null,
                color: const Color(0xFF00695C),
                onTap: () => pick(() => pos.selectTable('',
                    takeaway: true, type: OrderType.platformTakeaway)),
              ),

              // ---- 2) 堂食桌号 ----
              if (tables.isNotEmpty) ...[
                const Divider(height: 12),
                for (final t in tables) ...[
                  _PickerTile(
                    title: '${L10n.t('order.table')} $t',
                    subtitle: pos.openItemCountForTable(t) > 0
                        ? '${L10n.t('table.already')} ${pos.openItemCountForTable(t)}'
                        : L10n.t('table.empty'),
                    color: pos.openItemCountForTable(t) > 0
                        ? const Color(0xFFEF6C00)
                        : const Color(0xFF2E7D32),
                    onTap: () => pick(() => pos.selectTable(t)),
                  ),
                  for (final s in tableSplits[t] ?? const <Order>[])
                    splitTile(s),
                ],
              ],

              // ---- 3) 进行中的外卖单 ----
              if (takeaways.isNotEmpty) ...[
                const Divider(height: 12),
                for (final o in takeaways) ...[
                  _PickerTile(
                    // 有名字就把名字 + 单号放最显眼；没名字就是 `#号`
                    title: o.takeawayTag.isEmpty
                        ? orderTypeLabel(o.orderType)
                        : o.takeawayTag,
                    subtitle:
                        '${orderTypeLabel(o.orderType)} · ${o.itemCount} ${L10n.t('cart.items')}',
                    color: const Color(0xFF00838F),
                    onTap: () => pick(() => pos.focusOrder(o)),
                  ),
                  for (final s in takeawaySplits[o.id] ?? const <Order>[])
                    splitTile(s),
                ],
              ],

              // ---- 4) 兜底：母单已结账 / 桌号不在设置里，但分单还没结 ----
              if (looseSplits.isNotEmpty) ...[
                const Divider(height: 12),
                for (final s in looseSplits) splitTile(s),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L10n.t('common.cancel')),
          ),
        ],
      );
    },
  );
  return result == true;
}

/// 列表里的一行：颜色圆点 + 名称 + 小字（空桌 / 已有 N / 单号…）。
class _PickerTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color color;
  final bool indent;
  final VoidCallback onTap;

  const _PickerTile({
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.fromLTRB(indent ? 40 : 16, 0, 16, 0),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
      onTap: onTap,
    );
  }
}
