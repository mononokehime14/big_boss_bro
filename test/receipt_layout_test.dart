import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/data/settings_store.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/receipt_layout.dart';
import 'package:big_boss_bro/services/ticket_builder.dart';
import 'package:big_boss_bro/utils/format.dart';

ReceiptData _data({String paperWidth = '58'}) {
  return ReceiptData(
    storeName: '我的餐厅',
    headerLines: const ['Av. Reforma 123', 'Tel: 555-1234'],
    infoRows: const [
      ReceiptInfoRow('日期', '2026-01-01 12:30'),
      ReceiptInfoRow('单号', '20260101-001  桌号 8'),
      ReceiptInfoRow('收银员', 'ADMIN'),
    ],
    currency: '¥',
    paymentMethodLabel: '现金',
    lines: const [
      OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28, unit: '份'),
      OrderLine(name: '可乐', quantity: 1, unitPrice: 5),
    ],
    total: 61.0,
    thankyou: '谢谢光临',
    paperWidth: paperWidth,
    labels: const ReceiptLabels(
      labelTotal: '合计',
      labelPay: '支付方式',
    ),
  );
}

/// 是不是一条横线（`-----` / `=====`）。
bool _isDivider(String s) {
  final t = s.trim();
  return t.length >= 8 && RegExp(r'^[-=]+$').hasMatch(t);
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

    test('包含店名、店头信息、总金额、谢谢光临', () {
      final text = buildReceiptLines(_data()).join('\n');
      expect(text, contains('我的餐厅'));
      expect(text, contains('Av. Reforma 123'));
      expect(text, contains('¥61.00'));
      expect(text, contains('谢谢光临'));
      expect(text, contains('牛肉炒饭'));
    });

    test('单头是「标签: 值」左对齐（跟参考小票一样）', () {
      final lines = buildReceiptLines(_data());
      final info = lines.firstWhere((l) => l.startsWith('日期:'));
      expect(info, startsWith('日期:'));
      expect(info, contains('2026-01-01 12:30'));
      // 标签列对齐：值的起始列一样
      final a = lines.firstWhere((l) => l.startsWith('单号:'));
      expect(a.indexOf('20260101-001'), info.indexOf('2026-01-01 12:30'));
    });

    test('菜品两行式：菜名(+单位) 金额一行，下一行「数量 x 单价」', () {
      final lines = buildReceiptLines(_data());
      final nameLine = lines.firstWhere((l) => l.contains('牛肉炒饭'));
      expect(nameLine.trimRight(), endsWith('¥56.00')); // 28 × 2
      final qtyLine = lines[lines.indexOf(nameLine) + 1];
      expect(qtyLine, contains('2 份 x'));
      expect(qtyLine, contains('¥28.00'));
    });

    test('合计单独夹在两条横线中间', () {
      final lines = buildReceiptLines(_data());
      final i = lines.indexWhere((l) => l.trimLeft().startsWith('合计'));
      expect(i, greaterThan(0));
      expect(_isDivider(lines[i - 1]), isTrue);
      expect(_isDivider(lines[i + 1]), isTrue);
      expect(lines[i], contains('¥61.00'));
    });
  });

  group('日期格式', () {
    test('中文用 年-月-日 24 小时', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 17, 5), 'zh'),
          '2026-09-20 17:05');
    });

    test('西语用 日/月/年 + a. m. / p. m.（跟参考小票一致）', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 5, 15), 'es'),
          '20/9/2026 5:15 a. m.');
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 17, 15), 'es'),
          '20/9/2026 5:15 p. m.');
    });

    test('英语用 AM / PM', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 0, 0), 'en'),
          '20/9/2026 12:00 AM');
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 12, 0), 'en'),
          '20/9/2026 12:00 PM');
    });
  });

  group('单子类型（堂食 / 外卖 / 电话外卖）', () {
    Order orderWith(OrderType type) => Order(
          id: '20260920-001',
          createdAt: DateTime(2026, 9, 20, 17, 15),
          lines: const [
            OrderLine(name: 'VERDURA CANTONES', quantity: 1, unitPrice: 140),
          ],
          total: 140,
          orderType: type,
        );

    String receipt(OrderType type) => TicketBuilder.receiptLines(
          orderWith(type),
          Settings(),
        ).map((l) => l.text).join('\n');

    String kitchen(OrderType type) => TicketBuilder.kitchenLines(
          orderWith(type),
          Settings(),
        ).map((l) => l.text).join('\n');

    test('电话外卖的小票上打「电话外卖」，不会跟普通外卖混在一起', () {
      final t = receipt(OrderType.phonecallTakeaway);
      expect(t, contains('电话外卖'));
    });

    test('厨房单上也打「电话外卖」（厨房才知道这是电话来的单）', () {
      expect(kitchen(OrderType.phonecallTakeaway), contains('电话外卖'));
    });

    test('堂食 / 外卖 的老文案没变', () {
      expect(receipt(OrderType.dineIn), contains('堂食'));
      final takeaway = receipt(OrderType.takeaway);
      expect(takeaway, contains('外卖'));
      // 「外卖」是「电话外卖」的一部分，所以要另外确认没串台
      expect(takeaway, isNot(contains('电话外卖')));
    });
  });

  group('厨师单字号', () {
    KitchenData kitchen({int fontSize = 1}) => KitchenData(
          table: '8',
          orderId: '20260920-001',
          createdAt: DateTime(2026, 9, 20, 17, 15),
          lines: const [
            OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28, unit: '份'),
          ],
          paperWidth: '58',
          fontSize: fontSize,
          labels: const KitchenLabels(
            title: '厨房单',
            labelTable: '桌号',
            colName: '菜名',
            colQty: '数量',
            append: '（追加）',
          ),
        );

    test('字号 1：正常列数（58mm = 32 列）', () {
      expect(kitchenColumns('58', 1), 32);
      for (final l in buildKitchenLines(kitchen())) {
        expect(displayWidth(l) <= 32, isTrue);
      }
    });

    test('字号 2（双倍高）：列数不变 —— 排版一个字都不动', () {
      expect(kitchenColumns('58', 2), 32);
      final normal = buildKitchenLines(kitchen());
      final large = buildKitchenLines(kitchen(fontSize: 2));
      expect(large, normal);
    });

    test('字号 3（双倍宽高）：列数减半，行仍然不超宽', () {
      expect(kitchenColumns('58', 3), 16);
      expect(kitchenColumns('80', 3), 24);
      for (final l in buildKitchenLines(kitchen(fontSize: 3))) {
        expect(displayWidth(l) <= 16, isTrue, reason: '行超宽: "$l"');
      }
    });
  });
}
