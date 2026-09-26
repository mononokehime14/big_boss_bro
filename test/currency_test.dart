import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/data/settings_store.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/sales_totals.dart';
import 'package:big_boss_bro/services/ticket_builder.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/utils/pricing.dart';

/// 币种与汇率（MXN / USD / RMB）：换算、结账、小票、日结。
///
/// 汇率口径：**1 个外币 = 多少本位币**（本位币 = 店里收钱的货币）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('换算 toForeign / toBase', () {
    test('本位币（汇率 1）不变', () {
      expect(toForeign(84, 1), 84);
      expect(toBase(84, 1), 84);
    });

    test('外币：应收 84、1 USD = 8.40 → 10 USD', () {
      expect(toForeign(84, 8.4), 10);
      expect(toBase(10, 8.4), 84);
    });

    test('没设汇率（0）就按 1:1 显示，不做瞎换算', () {
      expect(toForeign(84, 0), 84);
      expect(toBase(84, 0), 84);
    });

    test('小数保留两位', () {
      expect(toForeign(100, 3), 33.33);
      expect(toBase(33.33, 3), 99.99);
    });
  });

  group('设置里的币种与汇率', () {
    test('默认本位币是 MXN，本位币汇率恒为 1，其它币种没设就是 0', () {
      final s = Settings();
      expect(s.baseCurrency, 'MXN');
      expect(s.rateFor('MXN'), 1);
      expect(s.canPayWith('MXN'), isTrue);
      expect(s.rateFor('USD'), 0);
      expect(s.canPayWith('USD'), isFalse);
    });

    test('设过汇率就能用；填 0 等于清除', () {
      final s = Settings();
      s.setRate('USD', 18.5);
      s.setRate('RMB', 2.6);
      expect(s.rateFor('USD'), 18.5);
      expect(s.canPayWith('USD'), isTrue);
      s.setRate('USD', 0); // 清除
      expect(s.canPayWith('USD'), isFalse);
      expect(s.rateFor('RMB'), 2.6);
    });

    test('把本位币换成 USD 后，USD 恒为 1、MXN 要用存的汇率', () {
      final s = Settings(exchangeRates: {'MXN': 0.054, 'USD': 0});
      s.baseCurrency = 'USD';
      expect(s.rateFor('USD'), 1);
      expect(s.rateFor('MXN'), 0.054);
    });

    test('汇率存得住（重新读回来还在）', () async {
      final store = SettingsStore();
      final s = Settings(baseCurrency: 'MXN')
        ..setRate('USD', 18.5)
        ..setRate('RMB', 2.6);
      await store.save(s);

      final back = await store.load();
      expect(back.baseCurrency, 'MXN');
      expect(back.rateFor('USD'), 18.5);
      expect(back.rateFor('RMB'), 2.6);
    });
  });

  group('外币结账', () {
    test('现金收 USD：订单金额仍记本位币，实收/找零用 USD', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 84
      final order = pos.placeOrder(table: '1')!;
      expect(order.total, 84);

      final closed = pos.closeOrder(
        order.id,
        PaymentMethod.cash,
        currencyCode: 'USD',
        exchangeRate: 8.4,
        receivedAmount: 20,
        changeAmount: 10, // 应收 10 USD，给 20 找 10
        cashier: 'maria',
      )!;

      expect(closed.status, OrderStatus.completed);
      expect(closed.total, 84); // 本位币
      expect(closed.foreignDue(8.4), 10);
      expect(closed.currencyCode, 'USD');
      expect(closed.exchangeRate, 8.4);
      expect(closed.receivedAmount, 20);
      expect(closed.changeAmount, 10);
      expect(closed.isForeignCurrency, isTrue);
      // 已收 = 应收这个不变量必须成立（否则日结会飘）
      expect(closed.isFullyPaid, isTrue);
      expect(closed.paidAmount, 84);
    });

    test('本位币收款：exchangeRate 传 0（不需要换算），不算外币单', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '2')!;
      final closed = pos.closeOrder(
        order.id,
        PaymentMethod.cash,
        currencyCode: 'MXN',
        exchangeRate: 0, // 本币：不需要换算
        receivedAmount: 50,
        changeAmount: 22,
      )!;
      expect(closed.isForeignCurrency, isFalse);
      expect(closed.receivedAmount, 50);
      expect(closed.changeAmount, 22);
    });

    test('刷卡：没有实收/找零，汇率也归 0', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '3')!;
      final closed = pos.closeOrder(
        order.id,
        PaymentMethod.card,
        currencyCode: 'MXN',
        exchangeRate: 0,
      )!;
      expect(closed.paymentMethod, PaymentMethod.card);
      expect(closed.receivedAmount, isNull);
      expect(closed.changeAmount, isNull);
      expect(closed.exchangeRate, 0);
      expect(closed.isForeignCurrency, isFalse);
    });

    test('折扣照旧：先打折再记收款金额', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 56
      final order = pos.placeOrder(table: '1')!;
      final closed = pos.closeOrder(
        order.id,
        PaymentMethod.cash,
        discountType: DiscountType.percent,
        discountValue: 10,
      )!;
      expect(closed.total, closeTo(50.4, 0.001));
      expect(closed.paidAmount, closeTo(50.4, 0.001));
    });
  });

  group('小票上的币种、汇率与单位', () {
    Settings settings({String paperWidth = '58'}) => Settings(
          storeName: '我的餐厅',
          paperWidth: paperWidth,
        );

    test('外币现金：打币种、汇率、该币种应收、实收、找零', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '5')!;
      final closed = pos.closeOrder(
        order.id,
        PaymentMethod.cash,
        currencyCode: 'USD',
        exchangeRate: 8.4,
        receivedAmount: 20,
        changeAmount: 10,
        cashier: 'maria',
      )!;

      final text = TicketBuilder.receiptLines(closed, settings())
          .map((l) => l.text)
          .join('\n');
      expect(text, contains('USD'));
      expect(text, contains('8.40')); // 汇率
      expect(text, contains('10.00')); // 该币种应收
      expect(text, contains('20.00')); // 实收
      expect(text, contains('maria')); // 收银员
    });

    test('菜品的「单位」会打在数量后面（厨房单）', () {
      final pos = PosController();
      final item = sampleMenu.firstWhere((m) => m.id == 'h1');
      pos.addToCart(item);
      final order = pos.placeOrder(table: '1')!;

      // 把订单行手动带上单位（正常是 Excel 导入时带上的）
      final withUnit = order.copyWith(
        lines: [
          OrderLine(
            name: order.lines.first.name,
            quantity: 2,
            unitPrice: order.lines.first.unitPrice,
            unit: '份',
          ),
        ],
      );
      final text = TicketBuilder.kitchenLines(withUnit, settings())
          .map((l) => l.text)
          .join('\n');
      expect(text, contains('2 份'));
    });

    test('单位太长就只打数量（不把列挤歪）', () {
      final order = Order(
        id: 'o1',
        createdAt: DateTime(2026, 1, 1),
        lines: const [
          OrderLine(
              name: '牛肉', quantity: 2, unitPrice: 28, unit: '公斤公斤公斤'),
        ],
        total: 56,
      );
      final text = TicketBuilder.kitchenLines(order, settings())
          .map((l) => l.text)
          .join('\n');
      expect(text, isNot(contains('公斤')));
      expect(text, contains('牛肉'));
    });
  });

  group('日结里的币种', () {
    test('现金按客人付的币种分组，金额 = 实收 - 找零（钱箱里剩下的）', () {
      final pos = PosController();
      // 第一单 84：收 20 USD（1 USD = 8.40）→ 应收 10 USD，找零 10 USD
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final a = pos.placeOrder(table: '1')!;
      pos.closeOrder(a.id, PaymentMethod.cash,
          currencyCode: 'USD',
          exchangeRate: 8.4,
          receivedAmount: 20,
          changeAmount: 10);

      // 第二单 28：本币现金收 50 找 22
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final b = pos.placeOrder(table: '2')!;
      pos.closeOrder(b.id, PaymentMethod.cash,
          currencyCode: 'MXN',
          exchangeRate: 0,
          receivedAmount: 50,
          changeAmount: 22);

      final totals = computeSalesTotals(pos.completedOrders);
      expect(totals.total, 112); // 84 + 28，全是本位币
      expect(totals.cashByCurrency['USD'], 10); // 20 - 10，钱箱里的美元
      expect(totals.cashByCurrency['MXN'], 28); // 50 - 22
      expect(totals.orderCount, 2);
    });

    test('刷卡进「刷卡」，不进现金币种', () {
      final pos = PosController();
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1')); // 28
      final a = pos.placeOrder(table: '1')!;
      pos.closeOrder(a.id, PaymentMethod.card);

      final totals = computeSalesTotals(pos.completedOrders);
      expect(totals.card, 28);
      expect(totals.cashByCurrency, isEmpty);
      expect(totals.total, 28);
    });
  });
}
