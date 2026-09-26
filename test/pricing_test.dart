import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/utils/pricing.dart';

/// 折扣 / 税 的计算规则（**对不上账的 bug 最容易出在这里**，所以用测试钉死）。
void main() {
  group('round2 金额取整', () {
    test('两位小数四舍五入', () {
      expect(round2(0.1 + 0.2), 0.3);
      expect(round2(28.006), 28.01);
      expect(round2(61), 61.0);
    });
  });

  group('PriceBreakdown', () {
    test('没折扣没税：应收 = 小计', () {
      final p = PriceBreakdown.of(subtotal: 61);
      expect(p.subtotal, 61);
      expect(p.discount, 0);
      expect(p.tax, 0);
      expect(p.total, 61);
      expect(p.hasAdjustments, isFalse);
    });

    test('百分比折扣：100 减 10% = 90', () {
      final p = PriceBreakdown.of(
        subtotal: 100,
        discountType: DiscountType.percent,
        discountValue: 10,
      );
      expect(p.discount, 10);
      expect(p.net, 90);
      expect(p.total, 90);
    });

    test('固定金额折扣：不会减成负数（减 500 只减到 0）', () {
      final p = PriceBreakdown.of(
        subtotal: 100,
        discountType: DiscountType.amount,
        discountValue: 500,
      );
      expect(p.discount, 100);
      expect(p.total, 0);
    });

    test('百分比折扣超过 100 也只当 100 处理', () {
      final p = PriceBreakdown.of(
        subtotal: 100,
        discountType: DiscountType.percent,
        discountValue: 200,
      );
      expect(p.discount, 100);
      expect(p.total, 0);
    });

    test('价外税（另加）：100 + 16% → 税 16、应收 116', () {
      final p = PriceBreakdown.of(subtotal: 100, taxRate: 16, taxIncluded: false);
      expect(p.tax, 16);
      expect(p.total, 116);
    });

    test('价内含税：116 里含 16% → 税 16、应收还是 116', () {
      final p = PriceBreakdown.of(subtotal: 116, taxRate: 16, taxIncluded: true);
      expect(p.tax, 16);
      expect(p.total, 116);
      expect(p.net, 116);
    });

    test('先打折、后算税：200 减 10% = 180，再另加 16% → 208.80', () {
      final p = PriceBreakdown.of(
        subtotal: 200,
        discountType: DiscountType.percent,
        discountValue: 10,
        taxRate: 16,
        taxIncluded: false,
      );
      expect(p.discount, 20);
      expect(p.net, 180);
      expect(p.tax, 28.8);
      expect(p.total, 208.8);
    });

    test('负数/异常输入不会算出奇怪结果', () {
      final p = PriceBreakdown.of(subtotal: -50, taxRate: -10);
      expect(p.subtotal, 0);
      expect(p.total, 0);
    });
  });

  group('Order 里的金额与折扣', () {
    Order order({
      DiscountType discountType = DiscountType.none,
      double discountValue = 0,
      double taxRate = 0,
      bool taxIncluded = true,
    }) =>
        Order(
          id: 'o1',
          createdAt: DateTime(2026, 1, 1),
          lines: const [
            OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
            OrderLine(name: '可乐', quantity: 1, unitPrice: 5),
          ],
          total: 61,
          discountType: discountType,
          discountValue: discountValue,
          taxRate: taxRate,
          taxIncluded: taxIncluded,
        );

    test('小计 = 各行相加；明细跟着折扣/税走', () {
      final o = order(discountType: DiscountType.percent, discountValue: 10);
      expect(o.subtotal, 61);
      expect(o.discountAmount, 6.1);
      expect(o.computedTotal, 54.9);
    });

    test('打折标签：百分比 / 固定金额两种写法', () {
      expect(
        order(discountType: DiscountType.percent, discountValue: 10)
            .discountLabel('¥'),
        '-10%',
      );
      expect(
        order(discountType: DiscountType.amount, discountValue: 20)
            .discountLabel('¥'),
        '-¥20.00',
      );
      expect(order().discountLabel('¥'), '');
    });

    test('收款进度：已收 / 仍欠 / 收满判定', () {
      final o = order();
      final half = o.copyWith(payments: [
        Payment(
          method: PaymentMethod.cash,
          amount: 30,
          paidAt: DateTime(2026, 1, 1),
        ),
      ]);
      expect(half.paidAmount, 30);
      expect(half.remaining, 31);
      expect(half.isFullyPaid, isFalse);

      final rest = half.copyWith(payments: [
        ...half.payments,
        Payment(
          method: PaymentMethod.card,
          amount: 31,
          paidAt: DateTime(2026, 1, 1),
        ),
      ]);
      expect(rest.paidAmount, 61);
      expect(rest.remaining, 0);
      expect(rest.isFullyPaid, isTrue);
    });

    test('JSON 往返：折扣/税/多笔收款都存得住', () {
      final o = order(
        discountType: DiscountType.amount,
        discountValue: 5,
        taxRate: 16,
        taxIncluded: false,
      ).copyWith(
        payments: [
          Payment(
            method: PaymentMethod.cash,
            amount: 40,
            currencyCode: 'MXN',
            received: 50,
            change: 10,
            paidAt: DateTime(2026, 1, 1, 12),
            label: '1/2',
            cashier: 'maria',
          ),
          Payment(
            method: PaymentMethod.card,
            amount: 24.96,
            paidAt: DateTime(2026, 1, 1, 12, 5),
            label: '2/2',
          ),
        ],
        status: OrderStatus.completed,
        closedAt: DateTime(2026, 1, 1, 12, 5),
      );

      final back = Order.fromJson(o.toJson());
      expect(back.discountType, DiscountType.amount);
      expect(back.discountValue, 5);
      expect(back.taxRate, 16);
      expect(back.taxIncluded, isFalse);
      expect(back.payments.length, 2);
      expect(back.payments.first.currencyCode, 'MXN');
      expect(back.payments.first.cashier, 'maria');
      expect(back.payments[1].label, '2/2');
      expect(back.paidAmount, closeTo(64.96, 0.001));
    });

    test('旧数据（没有 payments / 折扣 / 税 字段）也能读回来', () {
      final legacy = {
        'id': 'old-1',
        'createdAt': '2026-01-01T12:00:00.000',
        'lines': [
          {'name': '牛肉炒饭', 'quantity': 2, 'unitPrice': 28},
        ],
        'total': 56.0,
        'paymentMethod': 'cash',
        'status': 'completed',
        'closedAt': '2026-01-01T12:30:00.000',
      };
      final o = Order.fromJson(legacy);
      expect(o.subtotal, 56);
      expect(o.discountType, DiscountType.none);
      expect(o.taxRate, 0);
      expect(o.taxIncluded, isTrue);
      expect(o.computedTotal, 56);
      // 老单没有收款记录 → 按「一次付清」补一条，日结的支付方式统计才不漏账
      expect(o.effectivePayments.length, 1);
      expect(o.effectivePayments.first.amount, 56);
      expect(o.paidAmount, 56);
      expect(o.isFullyPaid, isTrue);
    });
  });

  // 现金结账框里「实收」下面的快捷金额标签（正好 / 邻近整数）。
  group('快捷实收金额 quickReceivedAmounts', () {
    test('应收 240 → 正好 240 / 250 / 300', () {
      expect(quickReceivedAmounts(240), [240, 250, 300]);
    });

    test('应收 550（本身就是 50 的整数）→ 550 / 600 / 1000', () {
      expect(quickReceivedAmounts(550), [550, 600, 1000]);
    });

    test('应收 61 → 61 / 70 / 100', () {
      expect(quickReceivedAmounts(61), [61, 70, 100]);
    });

    test('带小数也不重复：245.5 → 245.5 / 250 / 300', () {
      expect(quickReceivedAmounts(245.5), [245.5, 250, 300]);
    });

    test('永远以「正好」开头，且严格递增', () {
      for (final due in [0.5, 7.0, 12.0, 99.9, 1234.0]) {
        final list = quickReceivedAmounts(due);
        expect(list.first, round2(due));
        for (var i = 1; i < list.length; i++) {
          expect(list[i], greaterThan(list[i - 1]));
        }
      }
    });
  });
}
