import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/account_menu.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/menu_area.dart';
import '../widgets/payment_flow.dart';

/// 点单主界面（Loyverse 风格）。
///
/// - 宽屏（收银机）：左边 60% 点菜、右边 40% **常驻购物车**。
///   **桌号 / 外卖在购物车顶部的下拉里选**（有菜的桌子用橙色标出）。
/// - 窄屏（手机）：菜单 + 底部购物车栏（点开弹窗，里面同样是那个下拉）。
///
/// 购物车下面两个按钮：**左「保存」（只记到单上）+ 右「厨房」（记到单上并打厨房单）**，
/// 见 `widgets/cart_panel.dart`；结账仍然在「订单」页做。
///
/// 点单区是两步：先显示「种类」，点进去再显示该种类的「菜品」。
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final pos = context.watch<PosController>();

    // 标题顺便显示当前桌/外卖，避免看错桌
    final target = !pos.hasTableSelected
        ? ''
        : pos.isPhoneTakeaway
            ? ' · ${L10n.t('order.phonecallTakeaway')}'
            : pos.isTakeaway
                ? ' · ${L10n.t('order.takeaway')}'
                : ' · ${L10n.t('order.table')} ${pos.selectedTable}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${settings.storeName}$target',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        // 右上角：当前账号（可以「锁定」换人）
        actions: const [AccountMenuButton()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏：左右分栏
          if (constraints.maxWidth >= 800) {
            return Row(
              children: [
                const Expanded(flex: 6, child: MenuArea()),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 4,
                  child: CartPanel(
                    onSave: () => saveOrderFlow(context),
                    onKitchen: () => kitchenOrderFlow(context),
                  ),
                ),
              ],
            );
          }

          // 窄屏：菜单 + 底部购物车栏
          return Column(
            children: [
              const Expanded(child: MenuArea()),
              // CartBottomBar 读 L10n 文案，不能 const，否则切语言不刷新
              CartBottomBar(),
            ],
          );
        },
      ),
    );
  }
}
