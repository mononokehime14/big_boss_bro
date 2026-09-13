import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/category.dart';
import 'package:big_boss_bro/models/menu_item.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/state/pos_controller.dart';

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

  test('decrement 到 0 会移除该行，购物车回到空', () {
    final pos = PosController();
    pos.addToCart(sampleMenu.first);
    expect(pos.cartCount, 1);
    pos.decrement(sampleMenu.first.id);
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
