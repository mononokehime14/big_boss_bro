import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/category_chips.dart';
import '../widgets/menu_grid.dart';
import '../widgets/payment_flow.dart';

/// 点单主界面（Loyverse 风格）。
///
/// - 宽屏（收银机）：左边 60% 点菜、右边 40% 常驻购物车，右下角是合计 + 下单。
/// - 窄屏（手机）：保持「菜单 + 底部购物车」的方式，购物车点开是弹窗。
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          settings.storeName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏：左右分栏
          if (constraints.maxWidth >= 800) {
            return Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      CategoryChips(),
                      const Expanded(child: MenuGrid()),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 4,
                  child: CartPanel(
                    onSubmit: (isAppend, table, appendOrderId) =>
                        placeOrAppendFlow(
                      context,
                      isAppend: isAppend,
                      table: table,
                      appendOrderId: appendOrderId,
                    ),
                  ),
                ),
              ],
            );
          }

          // 窄屏：菜单 + 底部购物车栏
          return Column(
            children: [
              // CategoryChips / CartBottomBar 读 L10n 文案，不能 const，否则切语言不刷新
              CategoryChips(),
              const Expanded(child: MenuGrid()),
              CartBottomBar(),
            ],
          );
        },
      ),
    );
  }
}
