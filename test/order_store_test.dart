import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/order_store.dart';
import 'package:big_boss_bro/models/order.dart';

void main() {
  test('OrderStore 保存后可读回（含中文/金额/支付方式）', () async {
    SharedPreferences.setMockInitialValues({});
    final store = OrderStore();

    final orders = [
      Order(
        id: '20260101-001',
        createdAt: DateTime(2026, 1, 1, 12, 30),
        lines: const [
          OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28.0),
          OrderLine(name: '可乐', quantity: 1, unitPrice: 5.0),
        ],
        total: 61.0,
        paymentMethod: PaymentMethod.cash,
      ),
    ];

    await store.save(orders);
    final loaded = await store.load();

    expect(loaded.length, 1);
    expect(loaded[0].id, '20260101-001');
    expect(loaded[0].total, 61.0);
    expect(loaded[0].paymentMethod, PaymentMethod.cash);
    expect(loaded[0].lines.length, 2);
    expect(loaded[0].lines[0].name, '牛肉炒饭');
    expect(loaded[0].lines[0].subtotal, 56.0);
  });
}
