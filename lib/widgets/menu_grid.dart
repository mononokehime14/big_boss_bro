import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 中间的菜品格子（emoji + 菜名 + 价格），点一下加入购物车。
class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;

    final items = pos.selectedCategoryId.isEmpty
        ? pos.menu
        : pos.menu.where((m) => m.categoryId == pos.selectedCategoryId).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _MenuCell(
        item: items[i],
        currency: settings.currencySymbol,
      ),
    );
  }
}

class _MenuCell extends StatelessWidget {
  final MenuItem item;
  final String currency;

  const _MenuCell({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final pos = context.read<PosController>();
          pos.addToCart(item);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text('${item.name} · ${money(item.price, currency)}'),
              duration: const Duration(milliseconds: 700),
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
                  Text(item.emoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 6),
                  Text(
                    item.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(item.price, currency),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF1FA85A),
                      fontWeight: FontWeight.w700,
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
