import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../utils/category_colors.dart';

/// 第一步：显示所有「种类」。每个种类一个颜色，点一下进入里面的菜品。
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final categories = pos.categories;

    // 每个种类下有几道菜
    final counts = <String, int>{};
    for (final m in pos.menu) {
      counts[m.categoryId] = (counts[m.categoryId] ?? 0) + 1;
    }

    if (categories.isEmpty) {
      return Center(
        child: Text(
          L10n.t('category.pick'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final cat = categories[i];
        final color = Color(categoryColorAt(cat.colorValue, i));
        return Card(
          color: color,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => pos.selectCategory(cat.id),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${counts[cat.id] ?? 0} ${L10n.t('cart.items')}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
