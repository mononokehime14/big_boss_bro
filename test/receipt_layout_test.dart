import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/receipt_layout.dart';
import 'package:big_boss_bro/utils/format.dart';

ReceiptData _data({String paperWidth = '58'}) {
  return ReceiptData(
    storeName: '我的餐厅',
    currency: '¥',
    orderId: '20260101-001',
    createdAt: DateTime(2026, 1, 1, 12, 30),
    paymentMethodLabel: '现金',
    lines: const [
      OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
      OrderLine(name: '可乐', quantity: 1, unitPrice: 5),
    ],
    total: 61.0,
    thankyou: '谢谢光临',
    paperWidth: paperWidth,
    labels: const ReceiptLabels(
      colName: '菜名',
      colQty: '数量',
      colUnit: '单价',
      colAmt: '金额',
      labelTotal: '合计',
      labelPay: '支付方式',
    ),
  );
}

void main() {
  group('money', () {
    test('加货币符号并保留两位', () {
      expect(money(28, '¥'), '¥28.00');
      expect(money(61.0, '¥'), '¥61.00');
      expect(money(5.5, '¥'), '¥5.50');
    });
  });

  group('中文宽度', () {
    test('中文按 2 列计', () {
      expect(displayWidth('牛肉炒饭'), 8);
      expect(displayWidth('ab'), 2);
      expect(displayWidth('可乐1'), 5);
    });

    test('padRight / padLeft / padCenter 使用显示宽度', () {
      expect(padRight('牛肉', 6), '牛肉  '); // 4 + 2
      expect(padLeft('¥9.00', 8).length, 8);
      expect(padCenter('餐厅', 8), '  餐厅  ');
    });
  });

  group('小票排版', () {
    test('58mm 每行不超过 32 列（不爆行）', () {
      final lines = buildReceiptLines(_data());
      for (final l in lines) {
        expect(displayWidth(l) <= 32, isTrue,
            reason: '行超宽: "$l" (${displayWidth(l)})');
      }
    });

    test('80mm 每行不超过 48 列', () {
      final lines = buildReceiptLines(_data(paperWidth: '80'));
      for (final l in lines) {
        expect(displayWidth(l) <= 48, isTrue);
      }
    });

    test('包含店名、总金额、谢谢光临', () {
      final text = buildReceiptLines(_data()).join('\n');
      expect(text, contains('我的餐厅'));
      expect(text, contains('¥61.00'));
      expect(text, contains('谢谢光临'));
      expect(text, contains('牛肉炒饭'));
    });
  });
}
