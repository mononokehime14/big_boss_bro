import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pos_controller.dart';
import 'category_grid.dart';
import 'menu_grid.dart';

/// 点单区（左半边）：
/// - 还没选种类 → 显示**种类**列表；
/// - 选了种类 → 显示该种类下的**菜品**，顶部条可以点回种类列表。
class MenuArea extends StatelessWidget {
  const MenuArea({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();

    if (pos.selectedCategoryId.isEmpty) {
      return const CategoryGrid();
    }
    return Column(
      children: [
        CategoryHeader(),
        const Expanded(child: MenuGrid()),
      ],
    );
  }
}
