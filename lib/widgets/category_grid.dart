import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart';
import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/category_colors.dart';
import '../utils/menu_sort.dart';
import 'reorderable_cell.dart';

/// 第一步：显示所有「种类」。每个种类一个颜色，点一下进入里面的菜品。
///
/// 顺序按排序条选的来（默认 / 首字母 / 流行度）—— 但**颜色永远按菜单里的
/// 原始顺序取**（`pos.categories` 的下标），否则换个排序颜色就跟着变了。
///
/// **默认**排序下，每个格子可以**长按拖动**换位置（见 `reorderable_cell.dart`），
/// 顺序只存在本机；内置的「自定义」那个格子不给拖（它永远排最后）。
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final mode = MenuSort.fromId(settings.menuSort);
    final categories = pos.categoriesSorted(mode, order: settings.menuOrder);
    // 「默认」= 本机记住的顺序，可以拖；另外两种是算出来的顺序，拖了没意义
    final canDrag = mode == MenuSort.natural;

    if (categories.isEmpty) {
      return Center(
        child: Text(
          L10n.t('category.pick'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // 格子比之前**大一点点**（字体放大了，要留得下）；名字太长就省略号
        maxCrossAxisExtent: 215,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final cat = categories[i];
        final colorIdx = pos.categories.indexWhere((c) => c.id == cat.id);
        final color =
            Color(categoryColorAt(cat.colorValue, colorIdx < 0 ? 0 : colorIdx));
        final cell = Card(
          color: color,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => pos.selectCategory(cat.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              // 格子高度是「宽度 ÷ childAspectRatio」算出来的**固定值**，
              // 名字长的种类会折成两行、系统字体调大时还可能更高 —— 所以：
              // ① 系统"字体大小"调得很大时，格子里最多按 1.2 倍显示；
              // ② LayoutBuilder 拿到格子的真实宽度 → 让文字照这个宽度正常折行；
              // ③ 外面套 FittedBox(scaleDown)：装得下就原样显示，装不下就**整体等比缩小**一点点，
              //    永远不溢出（不会出现黄黑条纹），也不会把字切掉。
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    // Center 是为了"内容比格子矮时仍然**垂直居中**"；
                    // 光有 FittedBox 的话内容会贴在格子顶部。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Text(
                          // 格子上**只有种类名**（原来的「N 件 · 已卖 M」去掉了）：
                          // 名字太长就省略号，格子不会为了显示全而变大
                          cat.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // 默认排序：长按这个格子可以拖到别的位置
        return ReorderableCell(
          id: cat.id,
          enabled: canDrag,
          // 内置的「自定义」种类永远排最后，不给拖（但可以拖到它上面 = 排到倒数第二）
          draggable: cat.id != kCustomCategoryId,
          onReorder: (movedId, targetId) => _reorder(
            context,
            categories.map((c) => c.id).toList(),
            movedId,
            targetId,
          ),
          child: cell,
        );
      },
    );
  }

  /// 拖动之后：把「所有种类」这组的新顺序写回全局顺序表（见 `utils/menu_sort.dart`）。
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

/// 第二步：顶部条显示当前种类，点一下回到种类列表。
class CategoryHeader extends StatelessWidget {
  const CategoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final idx = pos.categories.indexWhere((c) => c.id == pos.selectedCategoryId);
    final cat = idx >= 0 ? pos.categories[idx] : null;
    final color = idx >= 0
        ? Color(categoryColorAt(pos.categories[idx].colorValue, idx))
        : const Color(0xFF1FA85A);

    return Material(
      color: color,
      child: InkWell(
        onTap: pos.clearCategory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cat?.name ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                L10n.t('category.back'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
