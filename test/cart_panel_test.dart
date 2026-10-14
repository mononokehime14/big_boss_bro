import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/state/settings_controller.dart';
import 'package:big_boss_bro/widgets/cart_panel.dart';

/// 购物车面板下面那两个按钮（**保存 / 厨房**）到底能不能点。
///
/// 这里锁的是一个真出现过的 bug：
/// 「先点『保存』（菜记到单上、购物车空了）→ **厨房按钮跟着变灰，再也打不了厨房单**；
///  换到别的桌再回来也一样。」
/// 原因：两个按钮当时共用同一个条件「购物车里有新菜」，而「保存」正好把购物车清空了。
/// 正确规则：「厨房」只要**这张单上还有没下厨的菜**就得能点。
void main() {
  // 必须在**创建 PosController 之前**把 SharedPreferences 的假数据准备好，
  // 否则它构造函数里那次 `_loadOrders()` 会走到平台通道上（测试里没插件 → 报错）。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 把面板挂起来。回调只记次数 —— 按钮变灰时点了不会有任何回调。
  Future<({int Function() saved, int Function() kitchen, int Function() checkout})>
      pumpPanel(
    WidgetTester tester,
    PosController pos,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsCtl = SettingsController();
    await settingsCtl.load();

    var saved = 0;
    var kitchen = 0;
    var checkout = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PosController>.value(value: pos),
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtl),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CartPanel(
              onSave: () => saved++,
              onKitchen: () => kitchen++,
              onCheckout: () => checkout++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      saved: () => saved,
      kitchen: () => kitchen,
      checkout: () => checkout,
    );
  }

  testWidgets('购物车里有新菜：保存 / 厨房 / 结账 都能点', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);

    final calls = await pumpPanel(tester, pos);

    await tester.tap(find.text('厨房'));
    await tester.pumpAndSettle();
    expect(calls.kitchen(), 1, reason: '购物车里有新菜，厨房应该能点');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls.saved(), 1, reason: '购物车里有新菜，保存应该能点');

    // 结账：外卖客人当场点完就付钱走这条路（记单 → 直接开结账窗口）
    await tester.tap(find.text('结账'));
    await tester.pumpAndSettle();
    expect(calls.checkout(), 1, reason: '购物车里有新菜，结账应该能点');
  });

  testWidgets('先点「保存」之后：购物车空了，但「厨房」还能点（把没下厨的菜打出去）',
      (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    // 「保存」做的事：把购物车的菜记到单上（还没下厨）
    pos.placeOrder();
    expect(pos.cartEmpty, isTrue, reason: '保存之后购物车应该是空的');
    expect(pos.unsentLines(pos.inProgressOrders.first.id).length, 1,
        reason: '单上应该留着一道还没下厨的菜');

    final calls = await pumpPanel(tester, pos);

    await tester.tap(find.text('厨房'));
    await tester.pumpAndSettle();
    expect(calls.kitchen(), 1,
        reason: '购物车空但单上有未下厨的菜 → 厨房必须还能点（这是那个 bug）');

    // 保存没东西可存 → 点不动
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls.saved(), 0, reason: '购物车是空的，保存应该禁用');
  });

  testWidgets('换到别的桌再回来：那张单上没下厨的菜照样能打', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    pos.placeOrder(); // 保存到 1 号桌

    // 去 3 号桌逛一圈再回来
    pos.selectTable('3');
    pos.selectTable('1');

    final calls = await pumpPanel(tester, pos);
    await tester.tap(find.text('厨房'));
    await tester.pumpAndSettle();
    expect(calls.kitchen(), 1, reason: '回到原来的桌，未下厨的菜还能打给厨房');
  });

  testWidgets('购物车空 + 单上也没有菜：三个按钮都点不动', (tester) async {
    final pos = PosController();
    pos.selectTable('1');

    final calls = await pumpPanel(tester, pos);

    await tester.tap(find.text('厨房'));
    await tester.tap(find.text('保存'));
    await tester.tap(find.text('结账'));
    await tester.pumpAndSettle();
    expect(calls.kitchen(), 0);
    expect(calls.saved(), 0);
    expect(calls.checkout(), 0, reason: '没东西可结 → 结账按钮应该是灰的');
  });

  testWidgets('菜都下过厨房了（购物车空）→ 结账仍然能点：结的是这张还没结的单',
      (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder()!; // 保存
    pos.markOrderSent(order.id); // 厨房：都下过厨房了

    final calls = await pumpPanel(tester, pos);

    await tester.tap(find.text('结账'));
    await tester.pumpAndSettle();
    expect(calls.checkout(), 1,
        reason: '这一桌还有一张没结的单 → 结账必须还能点（客人要付钱了）');
  });
}
