import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart';
import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/format.dart';
import '../utils/menu_sort.dart';
import 'custom_item_dialog.dart';
import 'item_customize_dialog.dart';
import 'reorderable_cell.dart';

/// 菜品格子（某个种类下的菜 **或者搜索结果**）。
///
/// 格子**底色 = 所属种类的颜色**，上面**只写菜名**（价格不显示 —— 点开
/// 「点菜」框里会写清楚单价和合计；名字太长就省略号，格子不会为它变大）。
///
/// - **点一下**：无论有没有定制项，都开「点菜」对话框 ——
///   可以选定制项、填**特别备注（可以多条）**、改**份数**（默认 1）；
/// - **长按**：**默认排序**下 = **拖动排序**（顺序存在本机，见
///   `reorderable_cell.dart`）；首字母 / 流行度下 = 快速加一份（不弹框）。
///
/// 排序（默认 / 首字母 / 流行度）在 `menu_area.dart` 的排序条里选。
///
/// **搜索**（`PosController.menuSearching`）时这里显示的是**所有种类里**搜到的菜，
/// 每个格子按它自己的种类上色；这时候不能拖动（拖的顺序只在种类内才有意义）。
class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final mode = MenuSort.fromId(settings.menuSort);
    final searching = pos.menuSearching;

    final catId = pos.selectedCategoryId;
    final items = searching
        ? pos.searchItems(mode, order: settings.menuOrder)
        : (catId.isEmpty
            ? const <MenuItem>[]
            : pos.itemsSorted(catId, mode, order: settings.menuOrder));

    /// 这道菜的格子用什么底色：**它自己那个种类的颜色**（搜索时各菜可能不同种类）。
    Color bgOf(MenuItem item) {
      final i = pos.categories.indexWhere((c) => c.id == item.categoryId);
      return Color(i >= 0
          ? categoryColorAt(pos.categories[i].colorValue, i)
          : 0xFF1FA85A);
    }

    // 「默认」= 本机记住的顺序，可以拖；另外两种是算出来的顺序，拖了没意义。
    // 搜索时也不给拖（结果跨种类，顺序表按种类分组存）。
    final canDrag = mode == MenuSort.natural && !searching;

    if (items.isEmpty) {
      return Center(
        child: Text(
          L10n.t(searching ? 'menu.search.none' : 'category.empty'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // 格子比之前**大一点点**（名字的字体放大了，要留得下），
        // 常见的收银机窗口宽度下大约**一排 5 个**；名字太长会省略号（见下面 `_MenuCell`）
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return ReorderableCell(
          id: item.id,
          enabled: canDrag,
          // 内置的「自定义」那道菜不给拖（它在这个种类里只有一道）
          draggable: item.id != kCustomItemId,
          onReorder: (movedId, targetId) => _reorder(
            context,
            items.map((m) => m.id).toList(),
            movedId,
            targetId,
          ),
          child: _MenuCell(
            item: item,
            currency: settings.currencySymbol,
            background: bgOf(item),
            // 默认排序时，长按留着拖动用 —— 不然会一边拖一边加一份
            quickAdd: !canDrag,
          ),
        );
      },
    );
  }

  /// 拖动之后：把这**一个种类下的菜**的新顺序写回全局顺序表。
  void _reorder(
    BuildContext context,
    List<String> visibleIds,
    String movedId,
    String targetId,
  ) {
    final ctl = context.read<SettingsController>();
    ctl.setMenuOrder(applyVisibleOrder(
      ctl.settings.menuOrder,
      moveBefore(visibleIds, movedId, targetId),
    ));
  }
}

class _MenuCell extends StatelessWidget {
  final MenuItem item;
  final String currency;
  final Color background;

  /// 长按 = 快速加一份（**默认排序**下关掉，长按让给"拖动排序"）。
  final bool quickAdd;

  const _MenuCell({
    required this.item,
    required this.currency,
    required this.background,
    this.quickAdd = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 点一下：开点菜对话框（选定制项 / 填特别备注 / 定份数）。
        // 「自定义」那道菜不一样：先弹「金额 + 备注」（备注会当菜名）。
        onTap: () async {
          final pos = context.read<PosController>();
          if (item.id == kCustomItemId) {
            final r = await showCustomItemDialog(context);
            if (r == null) return;
            pos.addCustomItem(note: r.note, amount: r.amount);
            return;
          }
          final result = await showItemCustomizeDialog(context, item);
          if (result == null) return;
          pos.addToCart(
            item,
            selections: result.selections,
            notes: result.notes,
            // 备注的加价（「换炒饭 +70」）要跟着进购物车
            notePrices: result.notePrices,
            quantity: result.quantity,
          );
        },
        // 长按：**默认排序**下留给"拖动排序"（见 `quickAdd`），
        // 首字母 / 流行度下 = 常用的菜快速加一份（不弹框）。
        // 「自定义」没法定价，所以长按也走那个框（不能"直接 +1"）。
        onLongPress: !quickAdd
            ? null
            : () async {
                final pos = context.read<PosController>();
                if (item.id == kCustomItemId) {
                  final r = await showCustomItemDialog(context);
                  if (r == null) return;
                  pos.addCustomItem(note: r.note, amount: r.amount);
                  return;
                }
                // 「基础数量」列：几份起就加几份（例：套餐 2 份起）
                pos.addToCart(item, quantity: item.minQuantity);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: Text('${item.displayName} · '
                        '${item.minQuantity} ${L10n.t('cart.items')} · '
                        '${money(item.minUnitPrice * item.minQuantity, currency)}'),
                    duration: const Duration(milliseconds: 900),
                  ));
              },
        child: Padding(
          padding: const EdgeInsets.all(6),
          // FittedBox(scaleDown)：格子变小/变矮时把内容整体等比缩小，
          // 保证任何窗口尺寸下都不会溢出（黄黑条纹）。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: 130,
              child: Text(
                // 格子上**只有名字**（有昵称就用昵称，见 `MenuItem.displayName`）：
                // 价格在点开后的「点菜」框里写着；名字太长就省略号 —— 格子不会为了
                // 把名字显示全而变大
                item.displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
