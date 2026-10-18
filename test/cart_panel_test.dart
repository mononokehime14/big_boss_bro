import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/state/settings_controller.dart';
import 'package:big_boss_bro/widgets/cart_panel.dart';

/// 购物车面板下面那几个按钮（**保存 / 厨房 / 结账**）到底能不能点，以及**小屏的样子**。
///
/// 这里锁的是一个真出现过的 bug：
/// 「先点『保存』（菜记到单上、购物车空了）→ **厨房按钮跟着变灰，再也打不了厨房单**；
///  换到别的桌再回来也一样。」
/// 原因：两个按钮当时共用同一个条件「购物车里有新菜」，而「保存」正好把购物车清空了。
/// 正确规则：「厨房」只要**这张单上还有没下厨的菜**就得能点。
///
/// 另外还锁两条安卓实测的改进：
/// - **屏幕窄放不下文字时，三个按钮只剩图标**（不然字被挤成 `…`）；
/// - 购物车行**只显示 `×2`**（加减按钮、「点击可改」提示都去掉了），
///   **清空**搬进了桌号旁边的「⋮」菜单。
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
    PosController pos, {
    Size size = const Size(1200, 1400),
  }) async {
    tester.view.physicalSize = size;
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

    // 「保存」**不限次数**：购物车空着也能点（这次没有新菜而已，不会锁死按钮）
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls.saved(), 1, reason: '保存不限次数，空购物车也点得动');
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

  testWidgets('购物车空 + 单上也没有菜：只有「保存」还能点（不限次数）', (tester) async {
    final pos = PosController();
    pos.selectTable('1');

    final calls = await pumpPanel(tester, pos);

    await tester.tap(find.text('厨房'));
    await tester.tap(find.text('保存'));
    await tester.tap(find.text('结账'));
    await tester.pumpAndSettle();
    expect(calls.kitchen(), 0);
    expect(calls.saved(), 1, reason: '保存不限次数 —— 想保存就保存');
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

  testWidgets('屏幕窄放不下文字：保存 / 厨房 / 结账 **只显示图标**', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);

    // 300 逻辑宽（小屏手机）：三个词放不下 → 只留图标，长按才有提示
    await pumpPanel(tester, pos, size: const Size(300, 900));

    expect(find.text('保存'), findsNothing, reason: '放不下就别显示文字（会被挤成 …）');
    expect(find.text('厨房'), findsNothing);
    expect(find.text('结账'), findsNothing);
    // 图标还是在的（三个按钮都还能点）
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(find.byIcon(Icons.restaurant), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale), findsOneWidget);
  });

  testWidgets('购物车行只显示 `×1`；「清空」搬进了桌号旁边的「⋮」', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    expect(pos.cartEmpty, isFalse);

    await pumpPanel(tester, pos);

    // ---- 冗杂显示全去掉了：没有「点击可改」，也没有加减按钮 ----
    expect(find.text('点击可改'), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing,
        reason: '份数不在这里加减（点这一行进去改数字）');
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    // 份数只显示成 `×1`
    expect(find.text('×1'), findsOneWidget);
    // 「清空」不在列表上了
    expect(find.text('清空'), findsNothing);

    // ---- 清空：桌号 / 外卖 下拉旁边那个「⋮」→ 操作列表 → 清空 ----
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(pos.cartEmpty, isTrue, reason: '「⋮」菜单里的清空要真的清掉购物车');
  });

  // ---- 保存好 / 下过厨房的单也能在点餐页删掉（本轮新增）----

  testWidgets('「⋮ → 清空」对**已经保存的单**：确认后整张单删掉（不只是清购物车）',
      (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder()!; // 「保存」→ 购物车空了，单还在
    pos.markOrderSent(order.id); // 连厨房单都打过了也一样能删
    expect(pos.cartEmpty, isTrue);

    await pumpPanel(tester, pos);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    // 先弹确认（整张单要没了，不能一点就没）
    expect(find.text('删掉这张单？'), findsOneWidget,
        reason: '有进行中的单时要先确认');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(pos.findOrder(order.id), isNull, reason: '整张单应该被删掉');
    expect(pos.inProgressOrders, isEmpty);
  });

  testWidgets('删「最后一道菜」= 删整张单（会换一句更重的确认）', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder()!;
    expect(order.lines.length, 1);

    await pumpPanel(tester, pos);

    // 单上只有这一道菜，✕ 照样能点（以前是禁用的）
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('最后一道菜：删了整张单就没了'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(pos.findOrder(order.id), isNull, reason: '最后一道菜删掉 → 整张单没了');
    expect(pos.inProgressOrders, isEmpty);
  });

  testWidgets('删「最后一道菜」时可以取消：单和菜都还在', (tester) async {
    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder()!;

    await pumpPanel(tester, pos);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(pos.findOrder(order.id)?.lines.length, 1, reason: '取消了就什么都不动');
  });
}
