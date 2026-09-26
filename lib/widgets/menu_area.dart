import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/menu_sort.dart';
import 'category_grid.dart';
import 'menu_grid.dart';

/// 点单区（左半边）：
/// - 最上面一条**排序条**：默认（菜单顺序）/ 首字母 A-Z / 流行度；
/// - 还没选种类 → 显示**种类**列表；
/// - 选了种类 → 显示该种类下的**菜品**，顶部条可以点回种类列表。
///
/// 「流行度」= 卖出的份数，**结账确认**时累加（见 `PosController.closeOrder`）。
class MenuArea extends StatelessWidget {
  const MenuArea({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();

    return Column(
      children: [
        const MenuSortBar(),
        if (pos.selectedCategoryId.isEmpty)
          const Expanded(child: CategoryGrid())
        else ...[
          const CategoryHeader(),
          const Expanded(child: MenuGrid()),
        ],
      ],
    );
  }
}

/// 排序条：默认 / 首字母 / 流行度。选哪个存在设置里，重启还记得。
class MenuSortBar extends StatelessWidget {
  const MenuSortBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCtl = context.watch<SettingsController>();
    final current = MenuSort.fromId(settingsCtl.settings.menuSort);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Icon(Icons.sort, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            L10n.t('menu.sort'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(settingsCtl, current, MenuSort.natural,
                      L10n.t('menu.sort.natural')),
                  const SizedBox(width: 8),
                  _chip(settingsCtl, current, MenuSort.name,
                      L10n.t('menu.sort.name')),
                  const SizedBox(width: 8),
                  _chip(settingsCtl, current, MenuSort.popular,
                      L10n.t('menu.sort.popular')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    SettingsController ctl,
    MenuSort current,
    MenuSort mode,
    String label,
  ) {
    final selected = current == mode;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => ctl.setMenuSort(mode.id),
      label: Text(label),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: const Color(0xFF1FA85A),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : const Color(0xFF232829),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
