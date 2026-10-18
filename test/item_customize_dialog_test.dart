import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/models/menu_item.dart';
import 'package:big_boss_bro/models/menu_option_group.dart';
import 'package:big_boss_bro/state/settings_controller.dart';
import 'package:big_boss_bro/widgets/item_customize_dialog.dart';

/// 点菜 / 改菜对话框。
///
/// ⚠️ 这里锁的是一个**真崩过的 bug**：对话框里写
/// `for (final g in widget.item?.options ?? const [])` 时，兜底 `const []` 会让
/// 这个表达式的类型变成 `List<dynamic>`，循环变量 `g` 跟着变 `dynamic`，
/// 于是 `g.options.firstWhere(orElse: () => ...)` 在运行时抛
/// `type '() => dynamic' is not a subtype of type '(() => String)?' of 'orElse'`
/// ——**一打开点菜框就崩**。修法：兜底写成 `const <MenuOptionGroup>[]`。
void main() {
  const item = MenuItem(
    id: 'i1',
    name: 'Arroz con pollo',
    price: 100,
    emoji: '',
    categoryId: 'c1',
    options: [
      MenuOptionGroup(
        name: 'Size',
        options: ['Mediano', 'Grande'],
        prices: [0, 50],
      ),
    ],
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required MenuItem? menuItem,
    ItemEditResult? initial,
    /// 传进来的话，会把对话框「确认」的结果塞进去（方便断言存了什么）。
    List<ItemEditResult?>? captured,
    /// 预置的**常用备注**（存在这个菜品所属的种类 `c1` 下）。
    List<String> savedNotes = const [],

    /// 预置常用备注的加价（没列的 = 不改价，相当于"以前存的、没金额"的老备注）。
    Map<String, double> savedNotePrices = const {},
  }) async {
    // 把测试窗口开大一点：对话框里的内容能一次放完，**不用滚动**，
    // 这样点按钮不会因为「按钮被滚到屏幕边缘」而点空（踩过：第二次点
    // 「加进备注」没点中，备注没加成，后面的断言就找不到那个小标签了）。
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0; // 不设的话默认 3.0，逻辑尺寸又会变回 400×600
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settingsCtl = SettingsController();
    await settingsCtl.load();
    for (final n in savedNotes) {
      settingsCtl.addSavedNote('c1', n, price: savedNotePrices[n] ?? 0);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtl),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    final result = await showItemCustomizeDialog(
                      context,
                      menuItem,
                      initial: initial,
                    );
                    captured?.add(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('新增点菜：有定制项也能正常打开（不再崩）', (tester) async {
    await pumpDialog(tester, menuItem: item);

    expect(tester.takeException(), isNull);
    expect(find.text('Arroz con pollo'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Mediano'), findsOneWidget);
    expect(find.text('加入购物车'), findsOneWidget); // 新增模式
    expect(find.text('份数'), findsOneWidget);
  });

  testWidgets('编辑已有的一行：预选原来的选项 / 备注 / 份数', (tester) async {
    await pumpDialog(
      tester,
      menuItem: item,
      initial: const ItemEditResult(
        selections: ['Grande'],
        notes: ['不要香菜'],
        quantity: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('保存修改'), findsOneWidget); // 编辑模式
    expect(find.text('不要香菜'), findsOneWidget); // 原来的备注显示成标签
    expect(find.text('3'), findsOneWidget); // 份数预填
    // 原来选的是 Grande（+50）→ 小计 = (100+50) × 3
    expect(find.textContaining('450.00'), findsWidgets);
  });

  testWidgets('特别备注可以一条一条加：存一条 → 输入框清空 → 再存下一条',
      (tester) async {
    await pumpDialog(tester, menuItem: item);

    final noteField = find.byType(TextField).first; // 第一条是备注输入框
    final addBtn = find.text('加进备注');

    // 第一条：加完要**变成一个小标签**（InputChip），而且输入框要清空
    await tester.enterText(noteField, '不要香菜');
    await tester.tap(addBtn);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '不要香菜'), findsOneWidget,
        reason: '第一条备注应该变成小标签');
    expect(find.text('不要香菜'), findsOneWidget,
        reason: '输入框应该已经清空（只剩那个小标签）');

    // 第二条：接着填下一条
    await tester.enterText(noteField, '少盐');
    await tester.tap(addBtn);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '不要香菜'), findsOneWidget);
    final saltChip = find.widgetWithText(InputChip, '少盐');
    expect(saltChip, findsOneWidget, reason: '第二条备注也要变成小标签');

    // 小标签上的 ✕ 能单独去掉一条（InputChip 默认的删除图标是 Icons.cancel，
    // 这里不写死图标常量，只要求「标签里有且只有一个图标」= 那个 ✕）
    final removeBtn =
        find.descendant(of: saltChip, matching: find.byType(Icon));
    expect(removeBtn, findsOneWidget, reason: '备注小标签上应该有个 ✕');
    await tester.tap(removeBtn);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '少盐'), findsNothing);
    expect(find.widgetWithText(InputChip, '不要香菜'), findsOneWidget);
  });

  testWidgets('份数：默认 1，加号点两下变 3', (tester) async {
    await pumpDialog(tester, menuItem: item);

    final plus = find.byIcon(Icons.add_circle_outline);
    await tester.ensureVisible(plus);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    await tester.tap(plus);
    await tester.pumpAndSettle();
    // 份数 3，单价 100 → 合计 ¥300.00
    expect(find.textContaining('300.00'), findsWidgets);
  });

  testWidgets('菜单里已经找不到这道菜：也能打开（只改份数/备注）', (tester) async {
    await pumpDialog(
      tester,
      menuItem: null,
      initial: const ItemEditResult(
        selections: [],
        notes: [],
        quantity: 1,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('已经不在菜单里'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
  });

  // ---- 默认选择规则 ----
  // 只有**一个**选项的定制项 = 「加料」（例如 EXTRA BOBA）：默认不选，点一下才加钱。
  // 有多个选项的（例如 Size）默认选最便宜那个，免得一点开就贵一档。

  const bobaItem = MenuItem(
    id: 'i2',
    name: 'Taro Smoothie',
    price: 85,
    emoji: '',
    categoryId: 'c1',
    options: [
      MenuOptionGroup(
        name: 'EXTRA BOBA',
        options: ['Yes'],
        prices: [25],
      ),
    ],
  );

  testWidgets('只有一个选项的加料：默认不选（价格 = 原价）', (tester) async {
    await pumpDialog(tester, menuItem: bobaItem);

    expect(tester.takeException(), isNull);
    expect(find.text('EXTRA BOBA'), findsOneWidget);
    expect(find.text('（可不选）'), findsOneWidget);
    // 默认没选 → 还是原价 85
    expect(find.textContaining('85.00'), findsWidgets);
    expect(find.textContaining('110.00'), findsNothing);
  });

  testWidgets('加料：点一下加钱，再点一下取消', (tester) async {
    await pumpDialog(tester, menuItem: bobaItem);

    await tester.tap(find.text('Yes  +¥25.00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('110.00'), findsWidgets); // 85 + 25

    await tester.tap(find.text('Yes  +¥25.00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('110.00'), findsNothing);
    expect(find.textContaining('85.00'), findsWidgets);
  });

  testWidgets('加料存的是**组名**（小票上写 EXTRA BOBA，不写看不懂的 Yes）',
      (tester) async {
    final captured = <ItemEditResult?>[];
    await pumpDialog(tester, menuItem: bobaItem, captured: captured);

    await tester.tap(find.text('Yes  +¥25.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();

    expect(captured.single, isNotNull);
    expect(captured.single!.selections, ['EXTRA BOBA']);
    expect(captured.single!.quantity, 1);
  });

  testWidgets('Yes/No 那种（JARRA）：默认不加钱，选 No 也等于没加', (tester) async {
    // 奶茶 45 + JARRA Yes(+125) / No(+0) —— 你表里就是这么写的
    const drink = MenuItem(
      id: 'i3',
      name: 'TE HELADO',
      price: 45,
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(
          name: 'JARRA',
          options: ['Yes', 'No'],
          prices: [125, 0],
        ),
      ],
    );

    final captured = <ItemEditResult?>[];
    await pumpDialog(tester, menuItem: drink, captured: captured);

    // 默认不选 → 45
    expect(find.textContaining('45.00'), findsWidgets);
    expect(find.text('（可不选）'), findsOneWidget);

    // 点 No（不加钱）→ 还是 45，而且存下来是空的（不会在小票上写个「No」）
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.textContaining('45.00'), findsWidgets);
    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();
    expect(captured.single!.selections, isEmpty);

    // 再来一次，这次点 Yes → 45 + 125 = 170，存的是组名 JARRA
    final captured2 = <ItemEditResult?>[];
    await pumpDialog(tester, menuItem: drink, captured: captured2);
    await tester.tap(find.text('Yes  +¥125.00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('170.00'), findsWidgets);
    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();
    expect(captured2.single!.selections, ['JARRA']);
  });

  testWidgets('多个选项：默认选最便宜那个（= 菜单格子上的起价）', (tester) async {
    // Size: Mediano +0 / Grande +50，基础价 100 → 默认应该是 Mediano（100）
    await pumpDialog(tester, menuItem: item);

    expect(find.textContaining('100.00'), findsWidgets);
    expect(find.textContaining('150.00'), findsNothing);
  });

  // ---- 特别备注的**加价**（真实 bug：填了金额，框里的菜价一动不动）----
  //
  // 以前：备注框 / 加价框没有监听 → 一边打「换炒饭」和「70」，标题的菜价和
  // 底下的合计**都不刷新**，看着像"加价没生效"；而且标题用的是**不含加价**的单价。
  testWidgets('备注加价：一边填金额，标题的菜价就跟着变；确认后 notePrices 带着它',
      (tester) async {
    final captured = <ItemEditResult?>[];
    await pumpDialog(tester, menuItem: item, captured: captured);
    // 这道菜 100（Size 默认选 Mediano +0）

    final noteField = find.byType(TextField).first; // 备注输入框
    final priceField = find.byType(TextField).at(1); // 右边那个小金额框

    await tester.enterText(noteField, '换炒饭');
    await tester.enterText(priceField, '70');
    await tester.pumpAndSettle();

    // ① 还没点「加进备注」，标题的菜价就该是 100 + 70 = 170，而且把账拆开写出来
    expect(find.textContaining('170.00'), findsWidgets,
        reason: '加了 +70 之后标题/合计必须是 170，不能还写着 100');
    expect(find.textContaining('+70'), findsWidgets,
        reason: '标题下面应该有一行小字 `¥100.00 +70`（钱加在哪一眼看得出）');

    // ② 填完直接确认（**不点「加进备注」**——这就是收银员的实际操作）
    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();
    expect(captured.single!.notes, ['换炒饭']);
    expect(captured.single!.notePrices, [70],
        reason: '加价必须跟着备注一起交给购物车（否则点完还是原价）');
  });

  // ⚠️ 这条测试**故意不打字**：编辑一行时备注和加价是**预填**进来的，
  //    断言的是"标签上带价签 + 标题/合计含加价"这两件事（视觉回归）。
  //    "打字 → 价格跟着变"那条在上面（「备注加价：一边填金额…」）。
  testWidgets('编辑已有备注：标签上带着价签，标题/合计也含加价', (tester) async {
    await pumpDialog(
      tester,
      menuItem: item,
      initial: const ItemEditResult(
        selections: [],
        notes: ['换炒饭'],
        notePrices: [70],
        quantity: 1,
      ),
    );

    expect(tester.takeException(), isNull);
    // 备注标签上直接写着价签
    expect(find.widgetWithText(InputChip, '换炒饭 +70'), findsOneWidget,
        reason: '标签要写成 `换炒饭 +70`');
    // 标题的菜价 = 100 + 70，底下的合计也一样
    expect(find.textContaining('170.00'), findsWidgets,
        reason: '含备注加价的单价/合计要是 170');
  });

  testWidgets('备注不加金额：菜价不变，也不显示那行小字', (tester) async {
    await pumpDialog(tester, menuItem: item);

    await tester.enterText(find.byType(TextField).first, '不要香菜');
    await tester.pumpAndSettle();
    expect(find.textContaining('100.00'), findsWidgets);
    expect(find.textContaining('+0'), findsNothing);
  });

  // ---- 常用备注（以前存好的那些）的加价 ----
  //
  // ⚠️ 这里**不去点常用备注那个 chip**：在这个对话框里，测试点 chip 的中心/文字都会
  //    `warnIfMissed`（点空但不报错），备注加不进去，测试就假失败。
  //    chip 的点击留给真机手测；下面用"**打同样的备注文字**"这条稳定的路来验加价
  //    （产品上也做了同一件事：打常用备注的名字 = 点那个标签）。

  testWidgets('常用备注**存过**加价：标签写着 +70，打同样的备注也自动带 70', (tester) async {
    final captured = <ItemEditResult?>[];
    await pumpDialog(
      tester,
      menuItem: item,
      captured: captured,
      savedNotes: ['换炒饭'],
      savedNotePrices: {'换炒饭': 70},
    );

    // ① 常用备注标签上直接写着价签
    expect(find.textContaining('换炒饭 +70'), findsWidgets,
        reason: '设置里存过加价，标签就该写 `换炒饭 +70`');

    // ② 直接把这条备注的名字打进去（金额框不填）→ 自动用它存的加价
    await tester.enterText(
        find.byKey(const ValueKey('itemNoteField')), '换炒饭');
    await tester.pumpAndSettle();
    expect(find.textContaining('170.00'), findsWidgets,
        reason: '常用备注存了 +70，打这条备注就该自动变成 170');

    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();
    expect(captured.single!.notes, ['换炒饭']);
    expect(captured.single!.notePrices, [70],
        reason: '常用备注的加价要跟着进购物车');
  });

  testWidgets('常用备注**没存过**加价（以前的老备注）：打它不会加钱，自己填 70 才算',
      (tester) async {
    final captured = <ItemEditResult?>[];
    await pumpDialog(
      tester,
      menuItem: item,
      captured: captured,
      savedNotes: ['换炒饭'], // 没给加价 = 老的常用备注
    );

    // 标签上没有价签
    expect(find.textContaining('+70'), findsNothing);

    // 只打备注名字 → 不加钱（老备注没有金额）
    await tester.enterText(
        find.byKey(const ValueKey('itemNoteField')), '换炒饭');
    await tester.pumpAndSettle();
    expect(find.textContaining('100.00'), findsWidgets,
        reason: '老备注没存金额，打进去不该凭空加钱');

    // 再自己填 70 → 变 170，确认后带 70
    await tester.enterText(
        find.byKey(const ValueKey('itemNotePriceField')), '70');
    await tester.pumpAndSettle();
    expect(find.textContaining('170.00'), findsWidgets);

    await tester.tap(find.text('加入购物车'));
    await tester.pumpAndSettle();
    expect(captured.single!.notePrices, [70]);
  });
}
