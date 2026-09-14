import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/format.dart';
import 'item_customize_dialog.dart';

/// 某个种类下的菜品格子。
///
/// 格子**底色 = 所属种类的颜色**，文字直接显示菜名 + 价格（不再用图案占位）。
///
/// - 点一下：有「定制项」的菜 → 弹出个性化定制对话框；没有 → 直接加进购物车。
/// - 长按：无论有没有定制项，都弹出定制对话框（可加「其他备注」）。
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
        : pos.menu.where((m) => m.categoryId == catId).toList();

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
      ),
    );
  }
}

class _MenuCell extends StatelessWidget {
  final MenuItem item;
  final String currency;
  final Color background;

  const _MenuCell({
    required this.item,
    required this.currency,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 点一下：有定制项 → 弹定制窗；没有 → 直接加进购物车
        onTap: () {
          if (item.hasOptions) {
            showItemCustomizeDialog(context, item);
            return;
          }
          context.read<PosController>().addToCart(item);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text('${item.name} · ${money(item.price, currency)}'),
              duration: const Duration(milliseconds: 1200),
              action: SnackBarAction(
                label: L10n.t('custom.note'),
                onPressed: () => showItemCustomizeDialog(context, item),
              ),
            ));
        },
        // 长按：不管有没有定制项，都打开定制窗（可加「其他备注」）
        onLongPress: () => showItemCustomizeDialog(context, item),
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
                    money(item.price, currency),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
