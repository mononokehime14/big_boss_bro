import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/utils/format.dart';

/// **特别备注带金额**（「换炒饭 +70」「不要炒饭 -60」）这一套：
/// 钱怎么算、存到哪、老数据怎么办。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OrderLine 的备注加价', () {
    test('小计 = (单价 + 备注加价) × 份数（按**每份**加）', () {
      const line = OrderLine(
        name: '牛肉炒饭',
        quantity: 2,
        unitPrice: 28,
        notes: ['换炒饭', '不要洋葱'],
        notePrices: [70, -5],
      );
      expect(line.notePriceTotal, 65);
      expect(line.effectiveUnitPrice, 93); // 28 + 70 - 5
      expect(line.subtotal, 186); // 93 × 2
      // 明细文字带上价签
      expect(line.detail, '换炒饭 +70 · 不要洋葱 -5');
      // 不带价格的版本（厨房看的是这个）
      expect(line.note, '换炒饭 · 不要洋葱');
    });

    test('没有备注加价（老数据 / 不填）→ 跟以前完全一样', () {
      const line = OrderLine(name: '可乐', quantity: 3, unitPrice: 5);
      expect(line.notePriceTotal, 0);
      expect(line.effectiveUnitPrice, 5);
      expect(line.subtotal, 15);
      // 加价列表比备注少 → 缺的按 0 算，不会崩
      const partial = OrderLine(
        name: '可乐',
        quantity: 1,
        unitPrice: 5,
        notes: ['a', 'b'],
        notePrices: [10],
      );
      expect(partial.notePriceTotal, 10);
      expect(partial.effectiveUnitPrice, 15);
    });

    test('存成 JSON 再读回来：备注和加价都还在（老数据没有这个字段也不报错）', () {
      const line = OrderLine(
        name: '牛肉炒饭',
        quantity: 1,
        unitPrice: 28,
        notes: ['换炒饭'],
        notePrices: [70],
      );
      final back = OrderLine.fromJson(line.toJson());
      expect(back.notes, ['换炒饭']);
      expect(back.notePrices, [70]);
      expect(back.subtotal, 98);

      // 老数据（没有 notePrices）
      final old = OrderLine.fromJson(const {
        'name': '可乐',
        'quantity': 1,
        'unitPrice': 5,
        'notes': ['少冰'],
      });
      expect(old.notePrices, isEmpty);
      expect(old.subtotal, 5);
      expect(old.detail, '少冰');
    });

    test('正负号格式：整数不带小数尾巴', () {
      expect(signedAmount(70), '+70');
      expect(signedAmount(-60), '-60');
      expect(signedAmount(12.5), '+12.50');
      expect(signedAmount(0), '+0');
    });
  });

  group('点单：备注加价从购物车一路带到订单', () {
    test('购物车里算钱、下单后订单金额都对', () {
      final pos = PosController();
      final rice = sampleMenu.firstWhere((m) => m.id == 'h1'); // 牛肉炒饭 28
      pos.selectTable('1');
      pos.addToCart(
        rice,
        notes: ['换炒饭'],
        notePrices: [70],
        quantity: 2,
      );
      // 购物车：(28+70)×2
      expect(pos.cartSubtotal, 196);
      expect(pos.cartItems.single.detail, '换炒饭 +70');

      final order = pos.placeOrder()!;
      expect(order.lines.single.effectiveUnitPrice, 98);
      expect(order.lines.single.subtotal, 196);
      expect(order.total, 196);
    });

    test('同样的菜、备注加价不同 → 购物车里是**两行**', () {
      final pos = PosController();
      final rice = sampleMenu.firstWhere((m) => m.id == 'h1');
      pos.addToCart(rice, notes: ['换炒饭'], notePrices: [70]);
      pos.addToCart(rice, notes: ['换炒饭'], notePrices: [50]);
      expect(pos.cartItems.length, 2);
      // 一模一样才会并成一行
      pos.addToCart(rice, notes: ['换炒饭'], notePrices: [70]);
      expect(pos.cartItems.length, 2);
      expect(pos.cartItems.first.quantity, 2);
    });

    test('改一条已下单的行：加价改了 → 金额跟着变、这行变回「未下厨」', () {
      final pos = PosController();
      final rice = sampleMenu.firstWhere((m) => m.id == 'h1');
      pos.addToCart(rice, quantity: 1);
      final order = pos.placeOrder()!;
      pos.markOrderSent(order.id);
      expect(pos.findOrder(order.id)!.lines.single.sentToKitchen, isTrue);

      final updated = pos.updateOrderLine(
        order.id,
        0,
        selections: const [],
        notes: ['换炒饭'],
        notePrices: [70],
        quantity: 1,
      )!;
      expect(updated.lines.single.effectiveUnitPrice, 98);
      expect(updated.total, 98);
      expect(updated.lines.single.sentToKitchen, isFalse,
          reason: '改过的行要重新下厨房');
    });
  });
}
