import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/category.dart';
import 'package:big_boss_bro/models/menu_item.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/escpos.dart' show TicketScale;
import 'package:big_boss_bro/services/receipt_layout.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/utils/drink_category.dart';

/// 两条规则：
/// 1. **饮料算不算饮料**（按种类的名字认：`饮料` / `Bebida` / `Drinks`…）；
/// 2. **厨师单上饮料排在最后**，前面用一条虚线跟餐品分开。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('种类名字 → 是不是饮料', () {
    test('中文 / 西语 / 英语的常见叫法都认', () {
      for (final name in [
        '饮料',
        '饮品',
        '酒水',
        '冷饮',
        'Bebida',
        'BEBIDAS FRÍAS',
        'Refrescos',
        'Jugos',
        'Drinks',
        'Hot beverages',
      ]) {
        expect(isDrinkCategory(name), isTrue, reason: '「$name」应该是饮料');
      }
    });

    test('菜 / 主食 / 甜点 / 乱七八糟的名字都不算', () {
      for (final name in [
        '热菜',
        '主食',
        '凉菜',
        'Postres', // 西语「甜点」—— 别被 `te` 这种短词误伤
        'Extras',
        'Entradas',
        '',
      ]) {
        expect(isDrinkCategory(name), isFalse, reason: '「$name」不该算饮料');
      }
    });
  });

  group('厨师单：饮料排最后', () {
    /// 用示例菜单搭一个控制器（`h1` = 牛肉炒饭 热菜、`d1`/`d2` = 可乐/橙汁 饮料）。
    PosController posWith(List<String> ids) {
      final pos = PosController();
      for (final id in ids) {
        pos.addToCart(sampleMenu.firstWhere((m) => m.id == id));
      }
      return pos;
    }

    test('点单顺序 菜、饮料、菜 → 打出来是「菜、菜」+ 虚线 + 饮料', () {
      // 故意点成 菜 → 饮料 → 菜（现实里很常见：客人先点菜，中途加饮料，再加菜）
      final pos = posWith(['h1', 'd1', 'h2']);
      final order = pos.placeOrder(table: '1')!;

      final kitchen = pos.kitchenTicketLines(order.id);
      expect(kitchen.lines.map((l) => l.name).toList(), ['牛肉炒饭', '宫保鸡丁', '可乐']);
      expect(kitchen.drinksFrom, 2, reason: '第 2 行（从 0 数）开始是饮料');
    });

    test('没有饮料 → drinksFrom = -1（不插虚线）', () {
      final pos = posWith(['h1', 'h2']);
      final order = pos.placeOrder(table: '1')!;
      final kitchen = pos.kitchenTicketLines(order.id);
      expect(kitchen.drinksFrom, -1);
      expect(kitchen.lines.length, 2);
    });

    test('只有饮料 → 也不插虚线（drinksFrom = 0，排版那边要求 i > 0）', () {
      final pos = posWith(['d1', 'd2']);
      final order = pos.placeOrder(table: '1')!;
      final kitchen = pos.kitchenTicketLines(order.id);
      expect(kitchen.drinksFrom, 0);
      expect(kitchen.lines.map((l) => l.name).toList(), ['可乐', '橙汁']);
    });

    test('追单只补打新加的：并进已下厨的行也只打多出来的份数', () {
      final pos = posWith(['h1', 'd1']);
      final order = pos.placeOrder(table: '1')!;
      pos.markOrderSent(order.id); // 厨房已经收到
      // 再加一份可乐 + 一道热菜
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'd1'));
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      pos.appendToOrder(order.id);

      final kitchen = pos.kitchenTicketLines(order.id);
      // 追单只有「可乐 1 份」和「牛肉炒饭 1 份」要打，且饮料仍然在最后
      expect(kitchen.lines.map((l) => l.name).toList(), ['牛肉炒饭', '可乐']);
      expect(kitchen.lines.first.quantity, 1, reason: '只补打多出来的一份');
      expect(kitchen.drinksFrom, 1);
    });

    test('菜单里没有的种类（老单 / 换过菜单）当餐品处理，不会崩', () {
      final pos = PosController(
        categories: const [Category(id: 'x', name: '饮料')],
        menu: const [
          MenuItem(id: 'x1', name: '可乐', price: 5, emoji: '🥤', categoryId: 'x'),
        ],
      );
      // 菜单换成没了这道菜的样子之后，老行还留着（itemId 找不到 → 当餐品）
      pos.addToCart(sampleMenu.firstWhere((m) => m.id == 'h1'));
      final order = pos.placeOrder(table: '1')!;
      final kitchen = pos.kitchenTicketLines(order.id);
      expect(kitchen.drinksFrom, -1);
      expect(kitchen.lines.single.name, '牛肉炒饭');
    });
  });

  group('厨师单排版：饮料前面一条虚线', () {
    /// 票面上「只有 `-` 和空格」的一行 = 虚线（厨师单是 `- - - -`，中间有空格）。
    bool isDashRow(TicketRow r) =>
        r.scale == TicketScale.normal &&
        r.text.trim().isNotEmpty &&
        r.text.runes.every((c) => c == 0x2D || c == 0x20);

    KitchenData ticket(List<OrderLine> lines, {int drinksFrom = -1}) => KitchenData(
          table: '8',
          orderId: '20261018-007',
          createdAt: DateTime(2026, 10, 18, 13, 45),
          lines: lines,
          paperWidth: '58',
          drinksFrom: drinksFrom,
          labels: const KitchenLabels(
            title: '厨师单',
            labelTable: '桌号',
            colName: '菜名',
            colQty: '数量',
            colNote: '备注',
            append: '(追加)',
            wait: '等待',
            minutes: '分钟',
          ),
        );

    test('drinksFrom 那行前面插一条虚线；没有饮料就只有结尾那条', () {
      const lines = [
        OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28),
        OrderLine(name: '可乐', quantity: 2, unitPrice: 5),
        OrderLine(name: '橙汁', quantity: 1, unitPrice: 8),
      ];

      List<TicketRow> rowsOf(int drinksFrom) =>
          buildKitchenRows(ticket(lines, drinksFrom: drinksFrom));

      final grouped = rowsOf(1);
      final plain = rowsOf(-1);
      expect(
        grouped.where(isDashRow).length,
        plain.where(isDashRow).length + 1,
        reason: '有饮料时多一条虚线（餐品 / 饮料之间的那条）',
      );

      // 虚线要正好插在「可乐」那行之前（行序：… 牛肉炒饭 … 虚线 … 可乐 …）
      final drinkAt = grouped.indexWhere((r) => r.text.contains('可乐'));
      expect(drinkAt, greaterThan(0));
      expect(isDashRow(grouped[drinkAt - 1]), isTrue,
          reason: '饮料那行上面应该紧挨着一条虚线');

      // 虚线上面（跳过"菜品之间空的那一行"）就是最后一道餐品
      final beforeDash = grouped.sublist(0, drinkAt - 1);
      final lastItemRow = beforeDash.lastWhere(
        (r) => r.text.trim().isNotEmpty && !isDashRow(r),
      );
      expect(lastItemRow.text.contains('牛肉炒饭'), isTrue,
          reason: '虚线上面是最后一道餐品');
    });
  });
}
