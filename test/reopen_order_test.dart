import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/state/pos_controller.dart';

/// **已结单回退成进行中**（收银员手快结错单时用）。
///
/// 这里把几条硬规则钉住：
/// - 只退**今天**结的；
/// - 堂食同桌 / 外卖同名已经有进行中单 → **不能退**（会认错单）；
/// - 分单的母单没了 → 不能退；
/// - 退回去之后收款记录清空、流行度扣回去，**再结一次也只算一次**。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Order placeOn(PosController pos, String table, List<int> menuIndexes) {
    pos.selectTable(table);
    for (final i in menuIndexes) {
      pos.addToCart(sampleMenu[i]);
    }
    return pos.placeOrder()!;
  }

  test('今天结的单：回退到进行中，收款清空、金额不变、流行度扣回去', () {
    final pos = PosController();
    final item = sampleMenu[0];
    final order = placeOn(pos, '1', [0]);
    final total = order.total;
    final salesBefore = pos.salesOfItem(item.id);

    pos.closeOrder(
      order.id,
      PaymentMethod.cash,
      currencyCode: 'USD',
      exchangeRate: 16.5,
      receivedAmount: 100,
      changeAmount: 20,
    );
    expect(pos.salesOfItem(item.id), salesBefore + 1);

    expect(pos.reopenOrder(order.id), isNull);

    final reopened = pos.findOrder(order.id)!;
    expect(reopened.isInProgress, isTrue);
    expect(reopened.closedAt, isNull);
    expect(reopened.payments, isEmpty);
    expect(reopened.paymentMethod, isNull);
    expect(reopened.currencyCode, '');
    expect(reopened.exchangeRate, 0);
    expect(reopened.receivedAmount, isNull);
    expect(reopened.changeAmount, isNull);
    expect(reopened.total, closeTo(total, 0.001), reason: '金额不能变');
    expect(reopened.reopenPending, isTrue, reason: '同步要知道这张单回退过');
    // 已结单列表里没了，回到进行中
    expect(pos.completedOrders.any((o) => o.id == order.id), isFalse);
    expect(pos.inProgressOrders.any((o) => o.id == order.id), isTrue);
    // 结账时加过的流行度要扣回去
    expect(pos.salesOfItem(item.id), salesBefore);
  });

  test('只退今天结的：昨天结的单不给退', () {
    final pos = PosController();
    final order = placeOn(pos, '1', [0]);
    pos.closeOrder(order.id, PaymentMethod.cash);
    final closed = pos.findOrder(order.id)!;

    // 模拟服务器拉下来一张"昨天结的"单
    pos.adoptServerOrders([
      closed.copyWith(closedAt: DateTime.now().subtract(const Duration(days: 1))),
    ]);

    expect(pos.reopenOrder(order.id), 'order.reopen.notToday');
    expect(pos.findOrder(order.id)!.isInProgress, isFalse);
  });

  test('同桌已经有另一张进行中的单：不能回退', () {
    final pos = PosController();
    final old = placeOn(pos, '1', [0]);
    pos.closeOrder(old.id, PaymentMethod.cash);

    // 客人又坐回 1 号桌，开了一张新单
    placeOn(pos, '1', [1]);

    expect(pos.reopenOrder(old.id), 'order.reopen.conflict');
    expect(pos.findOrder(old.id)!.isInProgress, isFalse);
  });

  test('外卖同名已经有进行中的单：不能回退；没名字的外卖每单独立，可以退', () {
    final pos = PosController();

    // 有名字的外卖
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu[0]);
    final named = pos.placeOrder()!;
    pos.setOrderLabel(named.id, '张三');
    pos.closeOrder(named.id, PaymentMethod.cash);

    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu[1]);
    final anotherNamed = pos.placeOrder()!;
    pos.setOrderLabel(anotherNamed.id, '张三');

    expect(pos.reopenOrder(named.id), 'order.reopen.conflict');

    // 没名字的外卖不按名字认单，不算冲突
    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu[0]);
    final unnamed = pos.placeOrder()!;
    pos.closeOrder(unnamed.id, PaymentMethod.cash);

    pos.selectTable('', takeaway: true);
    pos.addToCart(sampleMenu[1]);
    pos.placeOrder();

    expect(pos.reopenOrder(unnamed.id), isNull);
    expect(pos.findOrder(unnamed.id)!.isInProgress, isTrue);
  });

  test('分单：母单还在就能退；母单被删了就不能退', () {
    final pos = PosController();
    final parent = placeOn(pos, '1', [0, 1]);
    final split = pos.splitOrderLines(parent.id, [0])!;
    pos.closeOrder(split.id, PaymentMethod.cash);

    expect(pos.reopenOrder(split.id), isNull);
    expect(pos.findOrder(split.id)!.isInProgress, isTrue);
    expect(pos.findOrder(split.id)!.parentId, parent.id);
    expect(pos.splitsOf(parent.id).length, 1);

    // 再分一张、结掉、把母单删了 → 分单没有根，不能退
    final parent2 = placeOn(pos, '2', [0, 1]);
    final split2 = pos.splitOrderLines(parent2.id, [0])!;
    pos.closeOrder(split2.id, PaymentMethod.cash);
    pos.deleteOrder(parent2.id);

    expect(pos.reopenOrder(split2.id), 'order.reopen.parentMissing');
    expect(pos.findOrder(split2.id)!.isInProgress, isFalse);
  });

  test('回退后再结一次：流行度只算一次', () {
    final pos = PosController();
    final item = sampleMenu[0];
    final order = placeOn(pos, '1', [0]);
    final before = pos.salesOfItem(item.id);

    pos.closeOrder(order.id, PaymentMethod.cash);
    expect(pos.salesOfItem(item.id), before + 1);

    expect(pos.reopenOrder(order.id), isNull);
    expect(pos.salesOfItem(item.id), before);

    pos.closeOrder(order.id, PaymentMethod.cash);
    expect(pos.salesOfItem(item.id), before + 1, reason: '再结一次也只算一份');
    expect(pos.findOrder(order.id)!.isInProgress, isFalse);
    // 重新结账的单要整单 upsert：服务器可能还停在原来的 completed，
    // 走 close_order 的 CAS 会拒绝更新（见 Order.reopenPending）。
    expect(pos.findOrder(order.id)!.reopenPending, isTrue);
  });
}
