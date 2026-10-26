import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/order_label.dart';
import '../widgets/account_menu.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/menu_area.dart';
import '../widgets/payment_flow.dart';

/// 点单主界面（Loyverse 风格）。
///
/// - 宽屏（收银机）：左边 70% 点菜、右边 30% **常驻购物车**（7 : 3）。
///   **桌号 / 外卖在购物车顶部的下拉里选**（有菜的桌子用橙色标出）。
/// - 窄屏（手机）：菜单 + 底部购物车栏（点开弹窗，里面同样是那个下拉）。
///
/// 购物车下面三个按钮：**保存 / 厨房 / 结账**（见 `widgets/cart_panel.dart`）。
///
/// **没选桌/外卖时**：购物车里有菜也允许点这三个按钮 —— 流程会先弹
/// 「请选择桌号 / 外卖」列表，选完再继续保存 / 下厨 / 结账（见
/// `widgets/target_picker.dart`）。正常选了桌/外卖的单子，保存或下厨之后
/// **不会**把目标清掉，购物车继续停在那张单上；**在本页结账完成后**
/// 会清掉当前桌/外卖，回到未选择状态。
///
/// 点单区是两步：先显示「种类」，点进去再显示该种类的「菜品」。
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final pos = context.watch<PosController>();

    // 标题顺便显示当前桌/外卖（有名字/号也带上），避免看错单
    final open = pos.openOrderForSelectedTable();
    final tag = open?.takeawayTag ?? '';
    // 类型叫法跟着当前选的目标走（堂食 / 外卖 / 电话外卖 / 平台外卖）
    final String target;
    if (!pos.hasTableSelected) {
      target = '';
    } else if (pos.isTakeaway) {
      final type = orderTypeLabel(pos.selectedType);
      target = ' · ${tag.isEmpty ? type : '$type $tag'}';
    } else {
      target = ' · ${L10n.t('order.table')} ${pos.selectedTable}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${settings.storeName}$target',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
                // 7 : 3 —— 点菜区给大（菜名看得清、一屏放得下更多菜），购物车窄一点够用
                const Expanded(flex: 7, child: MenuArea()),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 3,
                  child: CartPanel(
                    onSave: () => saveOrderFlow(context),
                    onKitchen: () => kitchenOrderFlow(context),
                    // 结账：记单之后直接开这张单的结账窗口（外卖当场付钱用）
                    onCheckout: () => _checkout(context),
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
              CartBottomBar(
                onSave: () => saveOrderFlow(context),
                onKitchen: () => kitchenOrderFlow(context),
                onCheckout: () => _checkout(context),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 点单页「结账」：记单 → 结账窗口 → **结完后回到未选桌状态**。
  ///
  /// 取消结账窗口时 `checkoutOrderFlow` 返回 null，当前桌/外卖保持不变，
  /// 客人可以继续改单。
  Future<void> _checkout(BuildContext context) async {
    final closed = await checkoutOrderFlow(context);
    if (closed == null || !context.mounted) return;
    context.read<PosController>().clearTable();
  }
}
