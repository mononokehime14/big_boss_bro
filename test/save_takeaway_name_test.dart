import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/services/receipt_print_service.dart';
import 'package:big_boss_bro/services/stub_print_service.dart';
import 'package:big_boss_bro/state/auth_controller.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/state/settings_controller.dart';
import 'package:big_boss_bro/widgets/payment_flow.dart';

/// 外卖 / 电话外卖单：**「保存」不限次数，每次都能改名字 / 等待时间**。
///
/// 锁的是一个真实反馈过的 bug：
/// 「已经保存过（或点过厨房）的外卖单，购物车是空的，再按「保存」什么都不发生 ——
///   只弹一句『没有新菜要保存』，**改名完全没入口**」。
/// 现在：购物车空着按「保存」，只要当前是**进行中的外卖单**，照样弹名字 / 等待时间框。
///
/// ⚠️ 这里**故意不在输入框里打字**（`enterText` 在这种"弹窗里再弹窗"的流程里不稳，
/// 打不进去也不报错）。这几条只锁"框有没有弹出来 / 预填得对不对 / 按钮能不能按"；
/// "改了名字到底写没写进订单"由 `pos_controller_test.dart` 的 `setOrderLabel` 几条守着。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 摆一个「点单页底部那个保存按钮」，按下就调 [saveOrderFlow]。
  Future<void> pumpSaveButton(
    WidgetTester tester,
    PosController pos, {
    required SettingsController settingsCtl,
    required AuthController auth,
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PosController>.value(value: pos),
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtl),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<ReceiptPrintService>.value(value: UnsupportedPrintService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => saveOrderFlow(ctx),
                  child: const Text('保存'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<(PosController, SettingsController, AuthController)> rig() async {
    final pos = PosController();
    final settingsCtl = SettingsController();
    await settingsCtl.load();
    final auth = AuthController();
    await auth.load();
    return (pos, settingsCtl, auth);
  }

  testWidgets('购物车空着按「保存」：进行中的外卖单照样弹名字框', (tester) async {
    final (pos, settingsCtl, auth) = await rig();

    // 先开一张外卖单（= 之前保存过 / 点过厨房），**没起名字**
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
    final order = pos.placeOrder()!;
    pos.focusOrder(order);
    expect(pos.cartEmpty, isTrue, reason: '保存过之后购物车是空的');
    expect(order.label, '');

    await pumpSaveButton(tester, pos, settingsCtl: settingsCtl, auth: auth);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 名字 / 等待时间框出现（这就是以前"完全不起作用"的地方）
    expect(find.text('保存这张外卖单'), findsOneWidget,
        reason: '空购物车按「保存」也要能改外卖单的名字');
    expect(find.text('不用名字'), findsOneWidget, reason: '两个按钮都在');
    expect(find.text('等待时间（分钟）'), findsOneWidget,
        reason: '外卖单（不只是电话外卖）也问等待时间');

    // 点「不用名字」→ 框关掉，单子还在、还是没名字（不会丢单）
    await tester.tap(find.text('不用名字'));
    await tester.pumpAndSettle();
    expect(find.text('保存这张外卖单'), findsNothing, reason: '点完要关掉');
    expect(pos.findOrder(order.id), isNotNull, reason: '单子不能被弄丢');
    expect(pos.findOrder(order.id)!.isInProgress, isTrue,
        reason: '还是进行中的单（不是被删了 / 结账了）');
  });

  testWidgets('已经有名字的外卖单：按「保存」弹框、名字框里预填着原名', (tester) async {
    final (pos, settingsCtl, auth) = await rig();

    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
    final order = pos.placeOrder()!;
    pos.setOrderLabel(order.id, '张三');
    pos.focusOrder(pos.findOrder(order.id)!);
    expect(pos.cartEmpty, isTrue);

    await pumpSaveButton(tester, pos, settingsCtl: settingsCtl, auth: auth);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存这张外卖单'), findsOneWidget,
        reason: '有名字的单子按「保存」也要弹框（这样才能改名）');
    expect(find.text('张三'), findsWidgets, reason: '名字框里要预填原来的名字');

    // 名字是合法的 → 弹窗里的「保存」是能按的；按下去名字保持不变
    final saveBtn = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(saveBtn).onPressed, isNotNull,
        reason: '名字框里有合法名字时，保存按钮不能是灰的');
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    expect(find.text('保存这张外卖单'), findsNothing);
    expect(pos.findOrder(order.id)!.label, '张三', reason: '不改就保持原样');
  });

  testWidgets('堂食单：购物车空着按「保存」还是只提示"没有新菜"（不弹名字框）',
      (tester) async {
    final (pos, settingsCtl, auth) = await rig();

    pos.selectTable('1');
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
    pos.placeOrder();
    expect(pos.cartEmpty, isTrue);

    await pumpSaveButton(tester, pos, settingsCtl: settingsCtl, auth: auth);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存这张外卖单'), findsNothing,
        reason: '堂食单没有名字可改，不该弹名字框');
    expect(find.textContaining('没有新菜'), findsOneWidget);
  });
}
