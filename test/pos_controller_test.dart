import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/category.dart';
import 'package:big_boss_bro/models/menu_item.dart';
import 'package:big_boss_bro/models/menu_option_group.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/sales_totals.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/utils/menu_sort.dart';

void main() {
  setUp(() {
    // 让 OrderStore 里的 SharedPreferences 在测试中可用
    SharedPreferences.setMockInitialValues({});
  });

  test('点单：同菜数量+1，合计正确', () {
    final pos = PosController();
    final beef = sampleMenu.firstWhere((m) => m.id == 'h1'); // 牛肉炒饭 28
    pos.addToCart(beef);
    pos.addToCart(beef); // 再点一次 → 数量 2
    expect(pos.cartCount, 2);
    expect(pos.cartTotal, closeTo(56.0, 0.001));
  });

  test('下单→结账：下单生成进行中的单并清空购物车；结账后转已结单', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 数量2
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1')); // 可乐 5
    expect(pos.cartTotal, closeTo(61.0, 0.001));

    // 下单
    final order = pos.placeOrder(table: '5')!;
    expect(order.total, closeTo(61.0, 0.001));
    expect(order.table, '5');
    expect(order.status, OrderStatus.inProgress);
    expect(order.lines.length, 2);
    expect(order.lines[0].name, '牛肉炒饭');
    expect(order.lines[0].quantity, 2);
    expect(pos.cartEmpty, isTrue);
    expect(pos.inProgressOrders.length, 1);
    expect(pos.completedOrders.isEmpty, isTrue);

    // 结账
    final closed = pos.closeOrder(order.id, PaymentMethod.cash)!;
    expect(closed.status, OrderStatus.completed);
    expect(closed.paymentMethod, PaymentMethod.cash);
    expect(pos.inProgressOrders.isEmpty, isTrue);
    expect(pos.completedOrders.length, 1);
  });

  test('追单：把购物车追加进进行中的单', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
    final order = pos.placeOrder(table: '3')!;
    expect(order.total, closeTo(28.0, 0.001));

    // 再点一份可乐，追到同一张单
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1')); // 5
    final updated = pos.appendToOrder(order.id)!;
    expect(updated.lines.length, 2);
    expect(updated.total, closeTo(33.0, 0.001));
    expect(pos.inProgressOrders.length, 1);
    expect(pos.cartEmpty, isTrue);
  });

  // 结账窗口左边「删掉这道菜」按钮用的就是这个 API。
  group('结账窗口里删菜 removeOrderLine', () {
    test('删一行后：行数 / 小计 / 应收都跟着变，单还是原来那张（进行中）', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 牛肉炒饭 28
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 数量 2
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1')); // 可乐 5
      final order = pos.placeOrder(table: '5')!;
      expect(order.lines.length, 2);
      expect(order.total, closeTo(61, 0.001));

      final after = pos.removeOrderLine(order.id, 0)!; // 删掉牛肉炒饭那一行
      expect(after.id, order.id);
      expect(after.isInProgress, isTrue);
      expect(after.lines.length, 1);
      expect(after.lines.first.name, '可乐');
      expect(after.subtotal, closeTo(5, 0.001));
      expect(after.total, closeTo(5, 0.001));
      // 界面拿到的也是同一张单的最新状态
      expect(pos.findOrder(order.id)!.lines.length, 1);
    });

    test('带着税的单删菜：税按新的小计重算', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
      final order = pos.placeOrder(
        table: '1',
        taxRate: 16,
        taxIncluded: false, // 价外税：应收 = 小计 + 税
      )!;
      expect(order.total, closeTo(70.76, 0.001)); // 61 + 9.76

      final after = pos.removeOrderLine(order.id, 0)!;
      expect(after.subtotal, closeTo(5, 0.001));
      expect(after.taxAmount, closeTo(0.8, 0.001));
      expect(after.total, closeTo(5.8, 0.001));
    });

    test('只剩一道菜时不给删（删空就没法结账了）', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
      final order = pos.placeOrder(table: '1')!;
      expect(pos.removeOrderLine(order.id, 0), isNull);
      expect(pos.findOrder(order.id)!.lines.length, 1);
    });

    test('越界索引 / 已结单 都不能删', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
      final order = pos.placeOrder(table: '2')!;

      expect(pos.removeOrderLine(order.id, 99), isNull);
      expect(pos.removeOrderLine(order.id, -1), isNull);

      pos.closeOrder(order.id, PaymentMethod.cash);
      expect(pos.removeOrderLine(order.id, 0), isNull);
      expect(pos.findOrder(order.id)!.lines.length, 2);
    });
  });

  test('decrement 到 0 会移除该行，购物车回到空', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.first);
    expect(pos.cartCount, 1);
    // 注意：购物车用「菜 + 选项 + 备注」的复合键，不是菜品 id
    pos.decrement(pos.cartItems.first.key);
    expect(pos.cartEmpty, isTrue);
  });

  test('同一道菜不同选项/备注 = 不同的行', () {
    final pos = PosController();
    final beef = sampleMenu.first; // 牛肉炒饭
    pos.addToCart(beef); // 无选项
    pos.addToCart(beef); // 同菜同选项 → 数量 2，仍是一行
    expect(pos.cartItems.length, 1);
    expect(pos.cartCount, 2);

    pos.addToCart(beef, selections: const ['Grande']); // 大份 → 新的一行
    expect(pos.cartItems.length, 2);
    expect(pos.cartCount, 3);

    pos.addToCart(beef, notes: const ['米饭换面条']); // 有备注 → 又是新的一行
    expect(pos.cartItems.length, 3);

    // 选项/备注会带进订单行
    final order = pos.placeOrder(table: '2')!;
    expect(order.lines.length, 3);
    final withNote = order.lines.firstWhere((l) => l.note.isNotEmpty);
    expect(withNote.notes, ['米饭换面条']);
    final withOption = order.lines.firstWhere((l) => l.options.isNotEmpty);
    expect(withOption.options, ['Grande']);
    expect(withOption.detail, 'Grande');
  });

  test('份数可以直接给（点菜对话框默认 1，也可以一次加 3 份）', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.first, quantity: 3);
    expect(pos.cartCount, 3);
    expect(pos.cartItems.first.quantity, 3);
    // 同一道菜再加 2 份 → 并成一行 5 份
    pos.addToCart(sampleMenu.first, quantity: 2);
    expect(pos.cartItems.length, 1);
    expect(pos.cartCount, 5);
    // 0 或负数当 1 处理
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'), quantity: 0);
    expect(pos.cartItems.last.quantity, 1);
  });

  test('特别备注可以有好几条（一条一条加）', () {
    final pos = PosController();
    pos.addToCart(
      sampleMenu.first,
      notes: const ['不要香菜', '少盐'],
    );
    final item = pos.cartItems.first;
    expect(item.notes, ['不要香菜', '少盐']);
    expect(item.note, '不要香菜 · 少盐'); // 拼成一行显示 / 打印

    // 两条备注 vs 一条「不要香菜/少盐」不是同一行
    pos.addToCart(sampleMenu.first, notes: const ['不要香菜/少盐']);
    expect(pos.cartItems.length, 2);
  });

  test('改购物车里的行：点它 → 编辑框保存（updateCartItem）', () {
    final pos = PosController();
    const item = MenuItem(
      id: 'i2',
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
    pos.addToCart(item, selections: const ['Mediano']);
    final key = pos.cartItems.first.key;

    pos.updateCartItem(
      key,
      selections: const ['Grande'],
      notes: const ['加辣'],
      quantity: 2,
    );
    expect(pos.cartItems.length, 1);
    final updated = pos.cartItems.first;
    expect(updated.selections, ['Grande']);
    expect(updated.notes, ['加辣']);
    expect(updated.quantity, 2);
    expect(updated.unitPrice, 150); // 换了 Grande，单价跟着变
    expect(pos.cartTotal, 300);
  });

  // ---- Size 定制项：下单时把「组名 → 选项值」也记到单上 ----
  //
  // 光有 options（`Grande`）不够：厨师单的「数量」列要认 **Size** 这一组、
  // 按老板手写单的习惯换算（Grande→份数、Mediano→份数/2、Chico→①），
  // 见 receipt_layout.dart 的 kitchenQtyShorthandLabel。
  test('下单：Size 的「组名 → 值」记到单上，JSON 存得住、老数据也读得回', () {
    final pos = PosController();
    const item = MenuItem(
      id: 'i9',
      name: 'Chun Kun',
      price: 100,
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(
          name: 'Size',
          options: ['Chico', 'Mediano', 'Grande'],
          prices: [0, 20, 50],
        ),
      ],
    );
    pos.addToCart(item, selections: const ['Grande']);
    final o = pos.placeOrder(table: '1')!;
    final line = o.lines.first;

    // 老字段不变（小票 / 备注列还是靠它）
    expect(line.options, ['Grande']);
    // 新字段：组名 → 值
    expect(line.optionGroups, {'Size': 'Grande'});
    expect(line.optionInGroup('Size'), 'Grande');
    expect(line.optionInGroup('size'), 'Grande', reason: '组名不分大小写');
    expect(line.optionInGroup('辣度'), '');

    // 存盘 / 上云都走 JSON：这组信息要跟着走
    final back = OrderLine.fromJson(line.toJson());
    expect(back.optionGroups, {'Size': 'Grande'});
    expect(back.optionInGroup('Size'), 'Grande');

    // 升级前的老单（没有 optionGroups 字段）→ 空 map（厨师单照老规则打份数）
    final legacyJson = line.toJson()..remove('optionGroups');
    expect(OrderLine.fromJson(legacyJson).optionGroups, isEmpty);
  });

  test('加料开关（EXTRA BOBA）：组名 → 值也记下来', () {
    final pos = PosController();
    const item = MenuItem(
      id: 'i10',
      name: 'Matcha Smoothie',
      price: 100,
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(name: 'EXTRA BOBA', options: ['Yes'], prices: [25]),
      ],
    );
    pos.addToCart(item, selections: const ['EXTRA BOBA']);
    final o = pos.placeOrder(table: '2')!;
    expect(o.lines.first.optionGroups, {'EXTRA BOBA': 'EXTRA BOBA'});
    // 组名不是 Size → 厨师单数量列照常打份数
    // （换算逻辑本身在 receipt_layout_test.dart 里测，这里不引打印那套）
  });

  test('改已经下过厨房的行：内容变了整行重下厨房，只加份数就只补打多的', () {
    final pos = PosController();
    final beef = sampleMenu.firstWhere((m) => m.id == 'h1');
    pos.addToCart(beef);
    final order = pos.placeOrder(table: '1')!;
    pos.markOrderSent(order.id);
    expect(pos.findOrder(order.id)!.lines.first.sentToKitchen, isTrue);

    // 什么都不改 → 保持「已下厨」
    pos.updateOrderLine(order.id, 0,
        selections: const [], notes: const [], quantity: 1);
    expect(pos.findOrder(order.id)!.lines.first.sentToKitchen, isTrue);

    // 只加一份 → 这一行不再是"整行已下厨"，但厨房只补打**多出来的那 1 份**
    pos.changeOrderLineQuantity(order.id, 0, 1);
    final after = pos.findOrder(order.id)!;
    expect(after.lines.first.quantity, 2);
    expect(after.lines.first.sentToKitchen, isFalse);
    expect(after.lines.first.unsentQty, 1);
    expect(after.total, closeTo(56, 0.001));
    expect(pos.unsentLines(order.id).single.quantity, 1);
  });

  test('删除菜品会把购物车里它的所有行一起删掉', () {
    final pos = PosController();
    final beef = sampleMenu.first;
    pos.addToCart(beef);
    pos.addToCart(beef, selections: const ['Grande']);
    expect(pos.cartItems.length, 2);

    pos.deleteMenuItem(beef.id);
    expect(pos.cartEmpty, isTrue);
  });

  test('删除订单后列表清空', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.first);
    final order = pos.placeOrder(table: '1')!;
    pos.closeOrder(order.id, PaymentMethod.qr);
    expect(pos.completedOrders.length, 1);

    pos.deleteOrder(order.id);
    expect(pos.completedOrders.isEmpty, isTrue);
  });

  // ---------------- 选项加价 ----------------

  test('选项影响价格：单价 = 基础价 + 所选加价，并进到订单', () {
    final pos = PosController();
    const item = MenuItem(
      id: 'i1',
      name: 'Arroz con pollo',
      price: 100, // 基础价
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(
          name: 'Size',
          options: ['Mediano', 'Grande'],
          prices: [0, 50], // Grande 加 50
        ),
      ],
    );

    expect(item.unitPriceFor(['Mediano']), 100);
    expect(item.unitPriceFor(['Grande']), 150);
    expect(item.minUnitPrice, 100);

    pos.addToCart(item, selections: const ['Grande']);
    expect(pos.cartItems.first.unitPrice, 150);
    expect(pos.cartTotal, 150);

    pos.selectTable('1');
    final o = pos.placeOrder()!;
    expect(o.lines.first.unitPrice, 150);
    expect(o.total, 150);

    // 换一个规格是「另一行」，价格也不同
    pos.addToCart(item, selections: const ['Mediano']);
    expect(pos.cartItems.length, 1);
    expect(pos.cartItems.first.unitPrice, 100);
  });

  test('加料开关（单选项 / Yes-No）：默认不加钱，选了才加，单子上存组名', () {
    const item = MenuItem(
      id: 'i3',
      name: 'TE HELADO',
      price: 45,
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(name: 'JARRA', options: ['Yes', 'No'], prices: [125, 0]),
        MenuOptionGroup(name: 'EXTRA BOBA', options: ['Yes'], prices: [25]),
      ],
    );

    // 这两种都算「加料开关」（要不要加？），普通多选项（Size）不算
    expect(item.options[0].isToggle, isTrue);
    expect(item.options[1].isToggle, isTrue);

    // 菜单格子上显示的「起价」= 基础价（加料默认不加）
    expect(item.minUnitPrice, 45);
    expect(item.unitPriceFor(const []), 45);
    // 选了加料：在单子上存的是**组名**，所以按组名也要能算出钱
    expect(item.unitPriceFor(const ['JARRA']), 170); // 45 + 125
    expect(item.unitPriceFor(const ['EXTRA BOBA']), 70); // 45 + 25
    expect(item.unitPriceFor(const ['JARRA', 'EXTRA BOBA']), 195);

    // `No/Yes` 这种顺序（你表里 Lonche 那些就是这样）也要认出来是开关
    const reordered = MenuOptionGroup(
      name: 'Cambio Arroz',
      options: ['No', 'Yes'],
      prices: [0, 70],
    );
    expect(reordered.isToggle, isTrue);
    expect(reordered.togglePrice, 70);

    // 普通多选项：不是开关，起价 = 最便宜的那个
    const sized = MenuItem(
      id: 'i4',
      name: 'ARROZ',
      price: 0,
      emoji: '',
      categoryId: 'c1',
      options: [
        MenuOptionGroup(
          name: 'Size',
          options: ['Mediano', 'Grande'],
          prices: [140, 200],
        ),
      ],
    );
    expect(sized.options.first.isToggle, isFalse);
    expect(sized.minUnitPrice, 140);
    expect(sized.unitPriceFor(const ['Mediano']), 140);
    expect(sized.unitPriceFor(const ['Grande']), 200);
  });

  // ---------------- 先选桌 / 堂食外卖 ----------------

  test('先选桌：下单后同桌能查到来单，并统计已有菜数', () {
    final pos = PosController();
    expect(pos.hasTableSelected, isFalse);
    expect(pos.openOrderForSelectedTable(), isNull);

    pos.selectTable('5');
    expect(pos.hasTableSelected, isTrue);
    expect(pos.selectedTable, '5');
    expect(pos.isTakeaway, isFalse);

    pos.addToCart(sampleMenu.first);
    final o = pos.placeOrder()!;
    expect(o.table, '5');
    expect(o.orderType, OrderType.dineIn);

    // 同一桌再进来，应该能查到这张进行中的单
    expect(pos.openOrderForSelectedTable()?.id, o.id);
    expect(pos.openItemCountForTable('5'), 1);
    expect(pos.openItemCountForTable('6'), 0);
  });

  test('外卖：桌号为空、类型是外卖，且不会自动并入', () {
    final pos = PosController();
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.first);
    final o = pos.placeOrder()!;
    expect(o.orderType, OrderType.takeaway);
    expect(o.table, '');
    expect(o.isTakeaway, isTrue);
    expect(o.isPhoneTakeaway, isFalse);
    // 外卖每单独立：同一个「外卖」不会自动并进上一单
    expect(pos.openOrderForSelectedTable(), isNull);
  });

  test('电话外卖：跟外卖一样不用桌号，但类型 / 标签 / 统计单独一份', () {
    final pos = PosController();
    // 选「电话外卖」：takeaway: true + type 指定
    pos.selectTable('', takeaway: true, type: OrderType.phonecallTakeaway);
    expect(pos.hasTableSelected, isTrue);
    expect(pos.selectedTable, '');
    expect(pos.isTakeaway, isTrue, reason: '电话外卖也是「不用桌号」的单');
    expect(pos.isPhoneTakeaway, isTrue);
    expect(pos.selectedType, OrderType.phonecallTakeaway);

    pos.addToCart(sampleMenu.first); // 牛肉炒饭 28
    final o = pos.placeOrder()!;
    expect(o.orderType, OrderType.phonecallTakeaway);
    expect(o.table, '');
    expect(o.isTakeaway, isTrue);
    expect(o.isPhoneTakeaway, isTrue);
    // 每单独立（没有桌号可以认）
    expect(pos.openOrderForSelectedTable(), isNull);

    pos.closeOrder(o.id, PaymentMethod.cash);
    // 进行中/已结单的计数是按类型分开的
    expect(pos.openPhoneTakeawayCount, 0);
    expect(pos.openTakeawayCount, 0);

    // 再开一张普通外卖，两个计数器互不影响
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.first);
    final t = pos.placeOrder()!;
    expect(t.orderType, OrderType.takeaway);
    expect(pos.openTakeawayCount, 1);
    expect(pos.openPhoneTakeawayCount, 0);

    // 切回堂食：两个「外卖」标志都清掉
    pos.selectTable('1');
    expect(pos.isTakeaway, isFalse);
    expect(pos.isPhoneTakeaway, isFalse);
    expect(pos.selectedType, OrderType.dineIn);
  });

  // ---- 平台外卖（Uber / DiDi 这种 App 来的单）----
  test('平台外卖：流程跟电话外卖一样，但日结单独一行、平台刷卡单列', () {
    final pos = PosController();
    // 选「平台外卖」：跟电话外卖一样 takeaway: true + 指定 type
    pos.selectTable('', takeaway: true, type: OrderType.platformTakeaway);
    expect(pos.hasTableSelected, isTrue);
    expect(pos.selectedTable, '');
    expect(pos.isTakeaway, isTrue, reason: '平台外卖也是「不用桌号」的单');
    expect(pos.isPlatformTakeaway, isTrue);
    expect(pos.isPhoneTakeaway, isFalse);
    expect(pos.selectedType, OrderType.platformTakeaway);

    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h2')); // 宫保鸡丁 32
    final o = pos.placeOrder()!;
    expect(o.orderType, OrderType.platformTakeaway);
    expect(o.table, '');
    expect(o.isPlatformTakeaway, isTrue);
    // 进行中的平台外卖也能在下拉里认回来（没名字就靠单号）
    expect(pos.openTakeawayOrders().any((x) => x.id == o.id), isTrue);
    expect(pos.openPlatformTakeawayCount, 1);
    expect(pos.openTakeawayCount, 0);
    expect(pos.openPhoneTakeawayCount, 0);

    // **名字 + 等待时间**：跟电话外卖走同一套（保存名字 / 等待时间都能用）
    pos.setOrderLabel(o.id, 'Uber 张三', waitMinutes: 20);
    expect(pos.findOrder(o.id)!.label, 'Uber 张三');
    expect(pos.findOrder(o.id)!.waitMinutes, 20);

    // 平台单**刷卡** → 日结里单列「平台刷卡」
    pos.closeOrder(o.id, PaymentMethod.card);
    expect(pos.openPlatformTakeawayCount, 0);

    // 再来一单平台外卖，**收现金** → 并进「现金」
    pos.selectTable('', takeaway: true, type: OrderType.platformTakeaway);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd2')); // 橙汁 8
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.cash);

    // 普通外卖 5（刷卡）、堂食 28（现金）做对照
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.card);
    pos.selectTable('1');
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.cash);

    final totals = computeSalesTotals(pos.completedOrders);
    // 左侧：平台外卖单独一行
    expect(totals.platformTakeaway, closeTo(40, 0.001)); // 32 + 8
    expect(totals.dineIn, closeTo(28, 0.001));
    expect(totals.takeaway, closeTo(5, 0.001));
    // 右侧：平台刷卡单列，普通「刷卡」里**不含**它（不重复算）
    expect(totals.platformCard, closeTo(32, 0.001));
    expect(totals.card, closeTo(5, 0.001));
    // 平台收的**现金**并进「现金」（不单列）
    final cashTotal =
        totals.cashByCurrency.values.fold<double>(0, (a, b) => a + b);
    expect(cashTotal, closeTo(36, 0.001)); // 平台 8 + 堂食 28
    // 四行加起来 = 总营业额（不会漏账、不会重复）
    expect(
        totals.dineIn +
            totals.takeaway +
            totals.phoneTakeaway +
            totals.platformTakeaway,
        closeTo(totals.total, 0.001));
    expect(totals.total, closeTo(73, 0.001));
    expect(totals.nonCashTotal, closeTo(37, 0.001)); // 刷卡 5 + 平台刷卡 32
  });

  // ---- 外卖单：点完厨房还在购物车 / 下拉列表里（有名字没名字都要能认回来）----
  group('进行中的外卖单（openTakeawayOrders / focusOrder）', () {
    test('没起名字的外卖单点完厨房也在列表里，靠单号认；结账后消失', () {
      final pos = PosController();
      pos.selectTable('', takeaway: true);
      pos.addToCart(sampleMenu.first);
      final o = pos.placeOrder()!; // 「保存」
      pos.markOrderSent(o.id); // 「厨房」

      final list = pos.openTakeawayOrders();
      expect(list.length, 1, reason: '没起名字的外卖单也要留在列表里');
      expect(list.single.dailyNo, greaterThan(0));
      expect(list.single.takeawayTag, '#${o.dailyNo}',
          reason: '没名字就显示单号');

      // 从下拉 / 订单页把它调回购物车：之后「保存 / 厨房 / 结账」都算这张单
      pos.focusOrder(list.single);
      expect(pos.focusedOrder?.id, o.id);
      expect(pos.openOrderForSelectedTable()?.id, o.id,
          reason: '没名字的外卖单也要能认回来接着加菜');

      // 结账之后它就不再是"进行中" → 自然从列表里消失
      pos.closeOrder(o.id, PaymentMethod.cash);
      expect(pos.openTakeawayOrders(), isEmpty);
      expect(pos.focusedOrder, isNull);
    });

    test('列表按当天单号从小到大排（先开的在前），分单不算', () {
      final pos = PosController();
      pos.selectTable('', takeaway: true);
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1')); // 两道菜才分得动
      final a = pos.placeOrder()!;
      pos.selectTable('', takeaway: true, type: OrderType.phonecallTakeaway);
      pos.addToCart(sampleMenu.first);
      final b = pos.placeOrder()!;

      final list = pos.openTakeawayOrders();
      expect(list.map((o) => o.id).toList(), [a.id, b.id]);
      expect(list.first.dailyNo, lessThan(list.last.dailyNo));

      // 分单不出现在列表里（它跟着母单走）
      final split = pos.splitOrderLines(a.id, [0]);
      expect(split, isNotNull);
      expect(pos.openTakeawayOrders().any((o) => o.isSplit), isFalse);
      expect(pos.openTakeawayOrders().length, 2);
    });

    test('有名字的外卖单：标签是「名字 #号」', () {
      final pos = PosController();
      pos.selectTable('', takeaway: true);
      pos.addToCart(sampleMenu.first);
      final o = pos.placeOrder()!;
      pos.setOrderLabel(o.id, '张三');
      final tagged = pos.openTakeawayOrders().single;
      expect(tagged.takeawayTag, '张三 #${o.dailyNo}');
    });

    // 「保存」每次都会弹名字框 → 名字能改、能清、等待时间能改
    test('每次保存都能改名 / 改等待时间（clearName 才真的清名字）', () {
      final pos = PosController();
      pos.selectTable('', takeaway: true);
      pos.addToCart(sampleMenu.first);
      final o = pos.placeOrder()!;

      // 先起名 + 填等待时间
      pos.setOrderLabel(o.id, '张三', waitMinutes: 15);
      expect(pos.findOrder(o.id)!.label, '张三');
      expect(pos.findOrder(o.id)!.waitMinutes, 15);

      // 改名（名字框里预填着旧名字，改成新名字）
      pos.setOrderLabel(o.id, '李四');
      expect(pos.findOrder(o.id)!.label, '李四');
      expect(pos.findOrder(o.id)!.waitMinutes, 15, reason: '没传就保持原来的等待时间');

      // 只改等待时间、名字传空 → **不动名字**（老行为）
      pos.setOrderLabel(o.id, '', waitMinutes: 30);
      expect(pos.findOrder(o.id)!.label, '李四', reason: '空的 name 不等于要清掉');
      expect(pos.findOrder(o.id)!.waitMinutes, 30);

      // 「不用名字」= clearName：真的清掉，但等待时间留着
      pos.setOrderLabel(o.id, '', waitMinutes: 30, clearName: true);
      expect(pos.findOrder(o.id)!.label, '');
      expect(pos.findOrder(o.id)!.waitMinutes, 30);
      expect(pos.findOrder(o.id)!.takeawayTag, '#${o.dailyNo}',
          reason: '没名字了还能靠单号认');
    });
  });

  test('电话外卖 / 外卖 / 堂食 的日结统计是分开的三行', () {
    final pos = PosController();
    // 堂食 28
    pos.selectTable('1');
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.cash);
    // 外卖 5
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.cash);
    // 电话外卖 8
    pos.selectTable('', takeaway: true, type: OrderType.phonecallTakeaway);
    pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd2'));
    pos.closeOrder(pos.placeOrder()!.id, PaymentMethod.cash);

    final totals = computeSalesTotals(pos.completedOrders);
    expect(totals.dineIn, closeTo(28, 0.001));
    expect(totals.takeaway, closeTo(5, 0.001));
    expect(totals.phoneTakeaway, closeTo(8, 0.001));
    // 三行加起来 = 总营业额（不会漏账、不会重复）
    expect(totals.dineIn + totals.takeaway + totals.phoneTakeaway,
        closeTo(totals.total, 0.001));
    expect(totals.total, closeTo(41, 0.001));
  });

  test('换桌：clearTable 会回到「未选桌」', () {
    final pos = PosController();
    pos.selectTable('3');
    pos.clearTable();
    expect(pos.hasTableSelected, isFalse);
  });

  // ---------------- 现金 / 日结 ----------------

  test('现金结账：记下币种、实收、找零', () {
    final pos = PosController();
    pos.selectTable('2');
    pos.addToCart(sampleMenu.first); // 牛肉炒饭 28
    final o = pos.placeOrder()!;
    final closed = pos.closeOrder(
      o.id,
      PaymentMethod.cash,
      currencyCode: 'MXN',
      receivedAmount: 50,
      changeAmount: 22,
    )!;
    expect(closed.paymentMethod, PaymentMethod.cash);
    expect(closed.currencyCode, 'MXN');
    expect(closed.receivedAmount, 50);
    expect(closed.changeAmount, 22);
  });

  test('订单 JSON 能存住堂食/外卖与现金字段（重启不丢）', () {
    final o = Order(
      id: 'x1',
      createdAt: DateTime(2026, 1, 1, 12),
      lines: const [OrderLine(name: 'A', quantity: 1, unitPrice: 10)],
      total: 10,
      paymentMethod: PaymentMethod.cash,
      orderType: OrderType.takeaway,
      status: OrderStatus.completed,
      currencyCode: 'USD',
      receivedAmount: 20,
      changeAmount: 10,
    );
    final back = Order.fromJson(o.toJson());
    expect(back.orderType, OrderType.takeaway);
    expect(back.currencyCode, 'USD');
    expect(back.receivedAmount, 20);
    expect(back.changeAmount, 10);
    expect(back.isTakeaway, isTrue);
  });

  // 购物车下面两个按钮：左「保存」（只记单、不打单）/ 右「厨房」（记单 + 打厨房单）。
  // 区分靠 `OrderLine.sentQty`（厨房已经收到几份）→ `unsentQty`（还要补几份）。
  group('保存 / 厨房（sentQty）', () {
    test('刚下单的菜都是「未下厨」，markOrderSent 之后全变「已下厨」', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
      final order = pos.placeOrder(table: '5')!;

      expect(order.lines.every((l) => !l.sentToKitchen), isTrue);
      expect(pos.unsentLines(order.id).length, 2);

      final sent = pos.markOrderSent(order.id)!;
      expect(sent.lines.every((l) => l.sentToKitchen), isTrue);
      expect(pos.unsentLines(order.id), isEmpty);
      // 再调一次不会出事
      expect(pos.markOrderSent(order.id)!.lines.length, 2);
    });

    test('「保存」后再点的同款菜：**并进原来那一行**，厨房只补打多出来的份数', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
      final order = pos.placeOrder(table: '3')!;
      pos.markOrderSent(order.id); // 厨房已经收到这份了

      // 客人再点一份**一模一样**的菜 → 并进同一行（数量 2），不另起一行
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final after = pos.appendToOrder(order.id)!;
      expect(after.lines.length, 1);
      expect(after.lines[0].quantity, 2);
      // 厨房手上还是 1 份 → 这次只补打**多出来的那 1 份**
      expect(after.lines[0].sentQty, 1);
      expect(after.lines[0].unsentQty, 1);
      final pending = pos.unsentLines(order.id);
      expect(pending.length, 1);
      expect(pending.single.quantity, 1);
      expect(after.total, closeTo(56, 0.001));

      // 再点一次「厨房」→ 厨房手上就是 2 份了，不会再补打
      final sent = pos.markOrderSent(order.id)!;
      expect(sent.lines.single.sentQty, 2);
      expect(pos.unsentLines(order.id), isEmpty);
    });

    test('只有「菜名 + 单价 + 定制项 + 特别备注」全一样才并（备注不同算两道菜）', () {
      final pos = PosController();
      final dish = sampleMenu.firstWhere((m) => m.id == 'h1');
      pos.addToCart(dish);
      final order = pos.placeOrder(table: '3')!;
      pos.markOrderSent(order.id);

      // 备注不一样 → 必须另起一行（厨房要分开做）
      pos.addToCart(dish, notes: const ['不要洋葱']);
      final after = pos.appendToOrder(order.id)!;
      expect(after.lines.length, 2);
      expect(after.lines[1].notes, const ['不要洋葱']);
      expect(after.lines[1].sentQty, 0);
      expect(pos.unsentLines(order.id).length, 1);
    });

    test('还没下过厨房的行照旧合并数量（同菜同选项同备注）', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '3')!;
      // 没调 markOrderSent（= 只是「保存」过）→ 再加一份应该并成一行
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final after = pos.appendToOrder(order.id)!;
      expect(after.lines.length, 1);
      expect(after.lines.first.quantity, 2);
      expect(after.lines.first.sentToKitchen, isFalse);
      expect(after.lines.first.sentQty, 0);
    });

    test('只改份数：厨房只补打多出来的；减份数不补打', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '3')!;
      pos.markOrderSent(order.id);
      // 直接在「已在单上」那一行按 +
      final plus = pos.changeOrderLineQuantity(order.id, 0, 1)!;
      expect(plus.lines.single.quantity, 2);
      expect(plus.lines.single.sentQty, 1);
      final pending = pos.unsentLines(order.id);
      expect(pending.single.quantity, 1); // 只打多出来的那一份

      // 减一份：厨房已经做了，不用补打（账单少算就行）
      final minus = pos.changeOrderLineQuantity(order.id, 0, -1)!;
      expect(minus.lines.single.quantity, 1);
      expect(pos.unsentLines(order.id), isEmpty);
    });

    test('sentQty 能存住；老数据（只有 sentToKitchen）当作已下厨', () {
      final o = Order(
        id: 'x2',
        createdAt: DateTime(2026, 1, 1, 12),
        lines: const [
          OrderLine(name: 'A', quantity: 1, unitPrice: 10),
          OrderLine(name: 'B', quantity: 1, unitPrice: 20, sentQty: 1),
        ],
        total: 30,
      );
      final back = Order.fromJson(o.toJson());
      expect(back.lines[0].sentToKitchen, isFalse);
      expect(back.lines[1].sentToKitchen, isTrue);
      expect(back.lines[1].sentQty, 1);

      // 老数据：JSON 里没有 sentToKitchen / sentQty → 视为 true
      // （那时候下单一律打厨房单，所以老单的菜都是"厨房已经有了"）
      final legacy = Map<String, dynamic>.from(back.toJson());
      final line =
          Map<String, dynamic>.from((legacy['lines'] as List).first as Map);
      line.remove('sentToKitchen');
      line.remove('sentQty');
      legacy['lines'] = [line];
      expect(Order.fromJson(legacy).lines.first.sentToKitchen, isTrue);
    });
  });

  // 流行度：**结账确认**时按份数累加，点单区可以按它排序。
  group('流行度统计（结账时记账）', () {
    test('结账后：菜品和分类的份数都加上去了；没结账的不算', () {
      final pos = PosController();
      final beef = sampleMenu.firstWhere((m) => m.id == 'h1');
      final cola = sampleMenu.firstWhere((m) => m.id == 'd1');

      // 进行中的单（还没结账）→ 不统计
      pos.addToCart(beef, quantity: 2);
      final open = pos.placeOrder(table: '1')!;
      expect(pos.salesOfItem(beef.id), 0);

      // 结账 → 记 2 份
      pos.closeOrder(open.id, PaymentMethod.cash);
      expect(pos.salesOfItem(beef.id), 2);
      expect(pos.salesOfCategory(beef.categoryId), 2);

      // 再来一单结账 → 累加
      pos.addToCart(beef);
      pos.addToCart(cola, quantity: 3);
      final second = pos.placeOrder(table: '2')!;
      pos.closeOrder(second.id, PaymentMethod.cash);
      expect(pos.salesOfItem(beef.id), 3);
      expect(pos.salesOfItem(cola.id), 3);
      expect(pos.salesOfCategory(cola.categoryId), 3);
    });

    test('resetSales 清空统计', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.first);
      final o = pos.placeOrder(table: '1')!;
      pos.closeOrder(o.id, PaymentMethod.cash);
      expect(pos.salesOfItem(sampleMenu.first.id), 1);
      pos.resetSales();
      expect(pos.salesOfItem(sampleMenu.first.id), 0);
    });

    test('按流行度排序：卖得多的排前面', () {
      final pos = PosController();
      final cola = sampleMenu.firstWhere((m) => m.id == 'd1'); // 可乐
      // 可乐卖 5 份（橙汁 d2 一份都没卖）
      pos.addToCart(cola, quantity: 5);
      final o = pos.placeOrder(table: '1')!;
      pos.closeOrder(o.id, PaymentMethod.cash);

      expect(pos.salesOfItem('d1'), 5);
      expect(pos.salesOfItem('d2'), 0);
      expect(pos.salesOfCategory('drink'), 5);

      final byPopular = pos.itemsSorted('drink', MenuSort.popular);
      expect(byPopular.first.id, 'd1'); // 卖得最多的排第一
      // 分类按流行度：drink 卖过，应该排在没卖过的凉菜前面
      final cats = pos.categoriesSorted(MenuSort.popular);
      expect(cats.first.id, 'drink');
    });

    test('默认排序 = 菜单原本的顺序（Excel 导入的顺序）', () {
      final pos = PosController();
      final natural = pos.itemsSorted('drink', MenuSort.natural);
      final raw = sampleMenu.where((m) => m.categoryId == 'drink').toList();
      expect(natural.map((m) => m.id).toList(), raw.map((m) => m.id).toList());
    });
  });

  test('日结：只统计当天已结单，堂食/外卖分开', () {
    final pos = PosController();
    // 堂食现金单
    pos.selectTable('1');
    pos.addToCart(sampleMenu.first);
    final a = pos.placeOrder()!;
    pos.closeOrder(a.id, PaymentMethod.cash,
        currencyCode: 'MXN', receivedAmount: 50, changeAmount: 22);
    // 外卖刷卡单
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu.first);
    final b = pos.placeOrder()!;
    pos.closeOrder(b.id, PaymentMethod.card);
    // 一张还在进行中的单（不该计入日结）
    pos.selectTable('9');
    pos.addToCart(sampleMenu.first);
    pos.placeOrder();

    final key = PosController.dateKey(DateTime.now());
    final list = pos.completedOrdersOn(key);

    expect(list.length, 2);
    expect(list.where((o) => o.isTakeaway).length, 1);
    expect(list.where((o) => !o.isTakeaway).length, 1);
    final cashOrder =
        list.firstWhere((o) => o.paymentMethod == PaymentMethod.cash);
    expect(cashOrder.currencyCode, 'MXN');
    expect(cashOrder.receivedAmount, 50);
    // 昨天没有单
    final yesterday =
        PosController.dateKey(DateTime.now().subtract(const Duration(days: 1)));
    expect(pos.completedOrdersOn(yesterday), isEmpty);
  });

  test('菜单管理：新增分类/菜品可命中，恢复默认后还原', () {
    final pos = PosController();
    final origCatCount = pos.categories.length;

    final catId = pos.nextId();
    pos.addCategory(Category(id: catId, name: '汤', emoji: '🥣'));
    expect(pos.categories.length, origCatCount + 1);

    final itemId = pos.nextId();
    pos.addMenuItem(MenuItem(
        id: itemId, name: '蛋花汤', price: 12.0, emoji: '🥣', categoryId: catId));
    expect(pos.menu.any((m) => m.id == itemId), isTrue);

    pos.resetMenuToDefault();
    expect(pos.categories.length, origCatCount);
    expect(pos.categories.any((c) => c.id == catId), isFalse);
    expect(pos.menu.any((m) => m.id == itemId), isFalse);
  });
}
