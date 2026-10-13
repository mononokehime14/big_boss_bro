import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/state/settings_controller.dart';
import 'package:big_boss_bro/widgets/payment_flow.dart';

/// 结账窗口的规矩（**一个页面搞定**，这次改的正是这里）：
///
/// - 明细 + 小计/合计在**左边**，右边从上到下：应收 → 折扣 → 收款币种 → 支付方式 →
///   现金（实收 + 快捷金额 + 找零）/ 刷卡；
/// - 右下角只有 **`打印单子`**（打完留在本界面，可以再打）和 **`确认收款`**，**没有「取消」**；
/// - **不用先打纸也能收款**（这正是当初要改的那个不顺手的地方）。
void main() {
  // 必须在**创建 PosController 之前**把 SharedPreferences 的假数据准备好，
  // 否则它构造函数里那次 `_loadOrders()` 会走到平台通道上（测试里没插件 → 报错）。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 挂一张进行中的单，把结账窗口打开。
  ///
  /// 返回 `printCalls`：`printBill` 被调了几次（打纸的次数）。
  Future<int Function()> openCheckout(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pos = PosController();
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder();
    expect(order, isNotNull, reason: '先得有张进行中的单才能结账');

    final settingsCtl = SettingsController();
    await settingsCtl.load();

    var printCalls = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PosController>.value(value: pos),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showCheckoutDialog(
                  ctx,
                  order: order!,
                  settings: settingsCtl.settings,
                  cashier: 'ADMIN',
                  printBill: (Order o) async {
                    printCalls++;
                    return null; // null = 打成功
                  },
                ),
                child: const Text('打开结账'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开结账'));
    await tester.pumpAndSettle();

    return () => printCalls;
  }

  testWidgets('一个页面：下面是「打印单子」+「确认收款」，没有「取消」', (tester) async {
    await openCheckout(tester);

    expect(find.text('打印单子'), findsOneWidget);
    expect(find.text('确认收款'), findsOneWidget, reason: '收款按钮就在同一页');
    expect(find.text('取消'), findsNothing, reason: '明确不要「取消」按钮');
    expect(find.text('返回上一步'), findsNothing, reason: '一页搞定，不需要翻页了');
  });

  testWidgets('一页里就能收款：折扣 / 收款币种 / 支付方式 / 实收找零 都在，没打过纸也能收',
      (tester) async {
    final printCalls = await openCheckout(tester);

    // 收款要用的东西全在这一页上
    expect(find.text('折扣'), findsOneWidget);
    expect(find.text('收款币种'), findsOneWidget);
    expect(find.text('支付方式'), findsOneWidget);
    expect(find.textContaining('实收'), findsWidgets);
    expect(find.textContaining('找零'), findsWidgets);
    expect(find.textContaining('应收'), findsWidgets); // 应收跟着币种显示

    // 一次都没打纸，直接收款也应该能点
    await tester.tap(find.text('确认收款'));
    await tester.pumpAndSettle();
    expect(printCalls(), 0, reason: '收款不该顺手打纸 —— 打纸是左边那个按钮的事');
    expect(find.text('打印单子'), findsNothing, reason: '收了钱窗口就该关了');
  });

  testWidgets('点「打印单子」：打完留在本界面，还能再打一张', (tester) async {
    final printCalls = await openCheckout(tester);

    await tester.tap(find.text('打印单子'));
    await tester.pumpAndSettle();

    expect(printCalls(), 1);
    expect(find.text('再打一张'), findsOneWidget, reason: '打过纸了，按钮应该变成「再打一张」');
    expect(find.textContaining('已打印'), findsOneWidget,
        reason: '要能看出这单已经出过纸了');
    // 打印**不切页面**：收款那些操作还在
    expect(find.text('确认收款'), findsOneWidget);

    // 打完单子「去干别的」= 界面一直开着，回来点确认就能收款
    await tester.tap(find.text('确认收款'));
    await tester.pumpAndSettle();
    expect(printCalls(), 1, reason: '确认收款时不该再打一遍');
  });

  testWidgets('打过纸的标记：同一页上切支付方式也还在', (tester) async {
    final printCalls = await openCheckout(tester);

    await tester.tap(find.text('打印单子'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已打印'), findsOneWidget);

    // 切到刷卡（同一页上的操作），标记和打过的次数都不该变。
    //
    // ⚠️ 这里**不能**用 `pumpAndSettle`：刷卡那个银行卡动画是 `..repeat()` 的
    //    无限循环动画，永远等不到"静止"，会直接超时。
    //    所以只 pump 两帧（一帧处理点击、一帧把新状态画出来）。
    await tester.tap(find.text('刷卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('再打一张'), findsOneWidget);
    expect(find.textContaining('已打印'), findsOneWidget);
    expect(printCalls(), 1);
  });
}
