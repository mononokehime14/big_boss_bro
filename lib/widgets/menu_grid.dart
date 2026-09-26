import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/format.dart';
import '../utils/menu_sort.dart';
import 'item_customize_dialog.dart';

/// 某个种类下的菜品格子。
///
/// 格子**底色 = 所属种类的颜色**，文字直接显示菜名 + 价格（不再用图案占位）。
///
/// - **点一下**：无论有没有定制项，都开「点菜」对话框 ——
///   可以选定制项、填**特别备注（可以多条）**、改**份数**（默认 1）；
/// - **长按**：常用菜/饮料的快捷加一份（不弹框）。
///
/// 排序（默认 / 首字母 / 流行度）在 `menu_area.dart` 的排序条里选。
class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;

    final catId = pos.selectedCategoryId;
    final catIndex = pos.categories.indexWhere((c) => c.id == catId);
    final bg = Color(catIndex >= 0
        ? categoryColorAt(pos.categories[catIndex].colorValue, catIndex)
        : 0xFF1FA85A);

    final items = catId.isEmpty
        ? const <MenuItem>[]
        : pos.itemsSorted(catId, MenuSort.fromId(settings.menuSort));

    if (items.isEmpty) {
      return Center(
        child: Text(
          L10n.t('category.empty'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _MenuCell(
        item: items[i],
        currency: settings.currencySymbol,
        background: bg,
        soldCount: pos.salesOfItem(items[i].id),
      ),
    );
  }
}

class _MenuCell extends StatelessWidget {
  final MenuItem item;
  final String currency;
  final Color background;

  /// 这道菜一共卖了多少份（只用来在「按流行度排序」时显示一个小角标）。
  final int soldCount;

  const _MenuCell({
    required this.item,
    required this.currency,
    required this.background,
    this.soldCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 点一下：**都**开点菜对话框（选定制项 / 填特别备注 / 定份数）
        onTap: () async {
          final pos = context.read<PosController>();
          final result = await showItemCustomizeDialog(context, item);
          if (result == null) return;
          pos.addToCart(
            item,
            selections: result.selections,
            notes: result.notes,
            quantity: result.quantity,
          );
        },
        // 长按：常用的菜/饮料直接 +1（不弹框）
        onLongPress: () {
          final pos = context.read<PosController>();
          pos.addToCart(item);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content:
                  Text('${item.name} · ${money(item.minUnitPrice, currency)}'),
              duration: const Duration(milliseconds: 900),
            ));
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          // FittedBox(scaleDown)：格子变小/变矮时把内容整体等比缩小，
          // 保证任何窗口尺寸下都不会溢出（黄黑条纹）。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: 108,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // 有单位就写「¥140.00 / 份」（Excel 的「单位」列）
                    item.hasUnit
                        ? '${money(item.minUnitPrice, currency)} / ${item.unit}'
                        : money(item.minUnitPrice, currency),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 有备注的菜一眼能看出来（角标）
                  if (item.hasOptions) ...[
                    const SizedBox(height: 4),
                    Text(
                      L10n.t('custom.hasOptions'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  // 卖出份数（只在这道菜卖过之后才显示）：按流行度排序时一眼看出谁最火
                  if (soldCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${L10n.t('menu.sold')} $soldCount',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
