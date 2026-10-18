import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/utils/order_label.dart';

/// **移动单子** / **分单** 的纯逻辑（`PosController` 里那两段）。
///
/// 这两件事都在动钱（分单是"客人分开付钱"），所以这里把最容易出错的地方钉住：
/// - 移动：目标桌空着就换桌号；目标桌有单就**并单**（一张桌只留一张单）；
/// - 分单：菜是**挪走**的（母单 + 分单的合计加起来必须等于原来的合计）；
///   母单至少留一道菜；分单能继续往里面加菜。
void main() {
  // PosController 构造时会读 SharedPreferences（订单历史），测试里要先塞假数据
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 在 [table] 上开一张单，菜是 [menuIndexes] 这几道（各 1 份）。
  Order placeOrderOn(
    PosController pos,
    String table,
    List<int> menuIndexes,
  ) {
    pos.selectTable(table);
    for (final i in menuIndexes) {
      pos.addToCart(sampleMenu[i]);
    }
    return pos.placeOrder()!;
  }

  group('移动单子', () {
    test('目标桌空着：单子直接换到新桌号，菜和金额都不变', () {
      final pos = PosController();
      final order = placeOrderOn(pos, '5', [0, 1, 2]);
      final linesBefore = order.lines.length;
      final totalBefore = order.total;

      final moved = pos.moveOrderToTable(order.id, '3');
      expect(moved, isNotNull);
      expect(moved!.table, '3');
      expect(moved.lines.length, linesBefore);
      expect(moved.total, totalBefore);
      // 单号没变（还是同一张单，只是换了桌）
      expect(moved.id, order.id);
      // 5 号桌空了、3 号桌认得出这张单
      expect(pos.openItemCountForTable('5'), 0);
      pos.selectTable('3');
      expect(pos.openOrderForSelectedTable()?.id, order.id);
    });

    test('目标桌已经有单：菜**并进去**，原来那张单删掉（一桌一单）', () {
      final pos = PosController();
      final source = placeOrderOn(pos, '5', [0, 1]);
      final target = placeOrderOn(pos, '3', [2]);

      final moved = pos.moveOrderToTable(source.id, '3');
      expect(moved, isNotNull);
      // 并进去的是**目标桌那张**
      expect(moved!.id, target.id);
      expect(moved.lines.length, source.lines.length + target.lines.length);
      // 源单没了
      expect(pos.findOrder(source.id), isNull);
      // 钱：并完之后 = 两张单的菜加起来（这里没税没折扣）
      expect(moved.total,
          closeTo(source.total + target.total, 0.001));
      // 3 号桌只有一张进行中的单
      pos.selectTable('3');
      expect(pos.openOrderForSelectedTable()?.id, target.id);
    });

    test('已经在同一个桌号：什么都不做，返回原单', () {
      final pos = PosController();
      final order = placeOrderOn(pos, '5', [0]);
      final same = pos.moveOrderToTable(order.id, '5');
      expect(same?.id, order.id);
      expect(pos.findOrder(order.id)!.table, '5');
    });

    test('外卖单挪到桌上：顺便变成堂食（名字 / 等待时间清掉）', () {
      final pos = PosController();
      pos.selectTable('', takeaway: true);
      pos.addToCart(sampleMenu[0]);
      final order = pos.placeOrder()!;
      expect(order.isTakeaway, isTrue);

      final moved = pos.moveOrderToTable(order.id, '7');
      expect(moved!.table, '7');
      expect(moved.isTakeaway, isFalse);
      expect(moved.label, '');
    });
  });

  group('分单', () {
    test('分出新分单：菜挪走、名字是「…-分单1」、两边合计加起来不变', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1, 2]);
      final totalAll = parent.total;
      final firstLine = parent.lines.first.subtotal;

      final split = pos.splitOrderLines(parent.id, [0]);
      expect(split, isNotNull);
      expect(split!.isSplit, isTrue);
      expect(split.splitNo, 1);
      expect(split.parentId, parent.id);
      expect(split.table, '1', reason: '分单显示在同一个桌号下');
      expect(split.lines.length, 1);
      expect(split.total, closeTo(firstLine, 0.001));

      // 母单还在，而且少了一道菜
      final after = pos.findOrder(parent.id)!;
      expect(after.isInProgress, isTrue);
      expect(after.lines.length, 2);
      // 钱不多不少
      expect(split.total + after.total, closeTo(totalAll, 0.001));
      // 名字：`桌号 1-分单1`
      expect(orderPlaceLabel(split), contains('分单1'));
      expect(orderPlaceLabel(split), contains('1'));
    });

    test('母单至少要留一道菜（全选了不给分）', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1]);
      expect(pos.splitOrderLines(parent.id, [0, 1]), isNull);
      expect(pos.splitOrderLines(parent.id, const []), isNull);
      // 什么都没变
      expect(pos.findOrder(parent.id)!.lines.length, 2);
    });

    test('再分一次是「分单2」；也能挪进**已有的**分单', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1, 2, 3]);
      final s1 = pos.splitOrderLines(parent.id, [0])!;
      final s2 = pos.splitOrderLines(parent.id, [1])!;
      expect(s1.splitNo, 1);
      expect(s2.splitNo, 2);
      expect(pos.splitsOf(parent.id).length, 2);

      // 再挪一道进 s1
      final into = pos.splitOrderLines(parent.id, [0], intoSplitId: s1.id)!;
      expect(into.id, s1.id);
      expect(into.lines.length, 2);
      // 母单还剩 1 道
      expect(pos.findOrder(parent.id)!.lines.length, 1);
    });

    test('分单**单独结账**：母单还是进行中', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1]);
      final split = pos.splitOrderLines(parent.id, [0])!;

      pos.closeOrder(split.id, PaymentMethod.cash);
      expect(pos.findOrder(split.id)!.isInProgress, isFalse);
      expect(pos.findOrder(parent.id)!.isInProgress, isTrue);
      // 结完的分单不再出现在「这张母单的分单」里
      expect(pos.splitsOf(parent.id).isEmpty, isTrue);
    });

    test('选桌打开的是**母单**，不是分单', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1]);
      pos.splitOrderLines(parent.id, [0]);
      pos.selectTable('1');
      expect(pos.openOrderForSelectedTable()?.id, parent.id);
    });

    test('分单跟着母单换桌（移动单子之后桌号一致）', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1]);
      final split = pos.splitOrderLines(parent.id, [0])!;
      pos.moveOrderToTable(parent.id, '9');
      expect(pos.findOrder(parent.id)!.table, '9');
      expect(pos.findOrder(split.id)!.table, '9');
    });

    test('分单**还能继续往下分**：新分单挂同一个母单，号接着排，钱还是不变', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1, 2]);
      final totalAll = parent.total;

      // 先分两道给「分单1」
      final s1 = pos.splitOrderLines(parent.id, [0, 1])!;
      expect(s1.lines.length, 2);
      expect(s1.splitNo, 1);

      // 再从**分单1**里分一道出去 → 新的「分单2」，仍然挂在母单下
      final s2 = pos.splitOrderLines(s1.id, [0])!;
      expect(s2.parentId, parent.id, reason: '还是同一个母单的分单');
      expect(s2.splitNo, 2);
      expect(s2.lines.length, 1);
      expect(pos.findOrder(s1.id)!.lines.length, 1, reason: '分单1 留一道');

      // 整条线：母单 + 分单1 + 分单2（分单界面就是一排这样的卡片）
      final family = pos.familyOrders(parent.id);
      expect(family.length, 3);
      expect(family.first.id, parent.id);
      expect(family.map((o) => o.splitNo).toList(), [0, 1, 2]);
      // 从分单那边进这个界面，看到的也是同一条线
      expect(pos.familyOrders(s1.id).length, 3);
      expect(pos.rootIdOf(s2.id), parent.id);

      // 钱不多不少
      final sum = family.fold<double>(0, (a, o) => a + o.total);
      expect(sum, closeTo(totalAll, 0.001));
    });

    test('分单不能挪回自己', () {
      final pos = PosController();
      final parent = placeOrderOn(pos, '1', [0, 1, 2]);
      final s1 = pos.splitOrderLines(parent.id, [0, 1])!;
      expect(s1.lines.length, 2);
      // 目标是**它自己** → 拒绝（不然等于原地打转）
      expect(
        pos.splitOrderLines(s1.id, [0], intoSplitId: s1.id),
        isNull,
        reason: 'target 是刚刚那张单（自己）→ 拒绝',
      );
      expect(pos.findOrder(s1.id)!.lines.length, 2);
    });
  });
}
