import 'package:flutter/material.dart' hide Category;
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../state/pos_controller.dart';

/// 顶部的横排分类标签（全部 / 热菜 / 主食 / 饮料…）。
class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PosController>();

    // 第一个固定是「全部」。
    final all = Category(id: '', name: L10n.t('category.all'), emoji: '🍽️');
    final chips = [all, ...controller.categories];

    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = chips[i];
          final selected = controller.selectedCategoryId == cat.id;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) => controller.selectCategory(cat.id),
            avatar: Text(cat.emoji, style: const TextStyle(fontSize: 16)),
            label: Text(cat.name),
            selectedColor: const Color(0xFF1FA85A),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF232829),
              fontWeight: FontWeight.w600,
            ),
            showCheckmark: false,
            side: BorderSide(
              color: selected ? const Color(0xFF1FA85A) : Colors.grey.shade300,
            ),
          );
        },
      ),
    );
  }
}
