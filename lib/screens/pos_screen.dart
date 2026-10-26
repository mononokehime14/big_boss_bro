import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/order_label.dart';
import '../widgets/account_menu.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/menu_area.dart';
import '../widgets/payment_flow.dart';
import 'table_select_screen.dart';

/// 点单主界面（Loyverse 风格）。
///
/// **先进「选桌 / 选外卖」页**（见 [TableSelectScreen]）：选好之后才显示
/// 下面的点单界面 —— 这样不会出现"菜都点完了才发现桌号/外卖选错"的情况。
/// 点单界面左上角的 ← 可以回到选桌页重新选。
///
/// 点单界面本身：
/// - 宽屏（收银机）：左边 70% 点菜、右边 30% **常驻购物车**（7 : 3）。
///   **桌号 / 外卖在购物车顶部的下拉里选**（有菜的桌子用橙色标出）。
/// - 窄屏（手机）：菜单 + 底部购物车栏（点开弹窗，里面同样是那个下拉）。
///
/// 购物车下面三个按钮：**保存 / 厨房 / 结账**（见 `widgets/cart_panel.dart`）。
/// 保存或厨房成功、或者在本页直接结账真正完成后，会**自动回到选桌页**
/// （见 `_afterAction`），不用再手动点左上角。
///
/// 点单区是两步：先显示「种类」，点进去再显示该种类的「菜品」。
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  /// true = 还在选桌 / 选外卖；false = 已经进入点单界面。
  bool _picking = true;

  /// 点单界面左上角「←」：回到选桌页。
  ///
  /// 顺便清掉当前选中的桌 / 外卖（购物车里的菜**不清**：万一只是换目标，
  /// 点好的菜还能带过去）。清掉之后从订单页「编辑」过来的 focus 也不会
  /// 把选桌页立刻顶掉。
  void _backToPicker() {
    context.read<PosController>().clearTable();
    setState(() => _picking = true);
  }

  /// 在点单页按「保存 / 厨房 / 结账」后自动回选桌页。
  ///
  /// - 保存：返回刚记下的单（没菜可记时 null）；
  /// - 厨房：**厨房单真的打成功**才返回单（打印失败 / 跳过返回 null，留在原地可重打）；
  /// - 结账：只有**真正点完第二步「结束」**才返回已结的单；取消结账窗口返回 null，
  ///   这时留在点单页，客人还能继续改单。
  ///
  /// 成功之后清掉当前桌/外卖再回选桌页（不清购物车 —— 流程本身已经清过了），
  /// 这样选桌页不会因为还 focus 着外卖单又立刻把点单页顶回来。
  Future<void> _afterAction(Future<Order?> Function() action) async {
    final result = await action();
    if (!mounted || result == null) return;
    context.read<PosController>().clearTable();
    setState(() => _picking = true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final pos = context.watch<PosController>();

    if (_picking) {
      // 从「订单」页点「编辑」调过来时，focusOrder 已经把目标设好了 →
      // 不要再挡在选桌页，直接进点单界面。
      // 用 post-frame：build 里不能直接 setState。
      if (pos.focusedOrder != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _picking) setState(() => _picking = false);
        });
      }
      return TableSelectScreen(
        onSelected: () => setState(() => _picking = false),
      );
    }

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: L10n.t('pos.backToPick'),
          onPressed: _backToPicker,
        ),
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
                    onSave: () =>
                        _afterAction(() => saveOrderFlow(context)),
                    onKitchen: () =>
                        _afterAction(() => kitchenOrderFlow(context)),
                    // 结账：记单之后直接开这张单的结账窗口（外卖当场付钱用）
                    onCheckout: () =>
                        _afterAction(() => checkoutOrderFlow(context)),
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
                onSave: () => _afterAction(() => saveOrderFlow(context)),
                onKitchen: () =>
                    _afterAction(() => kitchenOrderFlow(context)),
                onCheckout: () =>
                    _afterAction(() => checkoutOrderFlow(context)),
              ),
            ],
          );
        },
      ),
    );
  }
}
