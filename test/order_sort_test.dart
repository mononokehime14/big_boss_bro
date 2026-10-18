import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/utils/order_sort.dart';

/// 「进行中」订单列表的几种排法（订单页那个小开关）。
///
/// - **默认（按单号）**：号大的在上面（号每天从 1 开始，堂食/外卖共用一条序列）；
/// - **按位置**：外卖 → 电话外卖 → 桌子（桌子按桌号清单的顺序）；
/// - **按时间**：最近保存 / 下厨房的在最上面。
///
/// 还有「已结单」那一页的排法（按单号 / 按结账时间 / 按金额）和**只看某一天**的筛选。
void main() {
  var seq = 0;

  /// 造一张单：`id` 用来看顺序，`updated` 是"最后动过的时间"。
  ///
  /// `closed` = 结账确认时间（不传就是"进行中"），`created` = 开单时间。
  Order order({
    required String id,
    String table = '',
    OrderType type = OrderType.dineIn,
    int dailyNo = 0,
    int updated = 0,
    double total = 10,
    DateTime? closed,
    DateTime? created,
  }) =>
      Order(
        id: id,
        createdAt:
            created ?? DateTime(2026, 10, 11, 10, 0).add(Duration(minutes: seq++)),
        updatedAt: DateTime(2026, 10, 11, 12, 0).add(Duration(minutes: updated)),
        lines: const [OrderLine(name: 'A', quantity: 1, unitPrice: 10)],
        total: total,
        table: table,
        orderType: type,
        dailyNo: dailyNo,
        status: closed == null ? OrderStatus.inProgress : OrderStatus.completed,
        closedAt: closed,
      );

  List<String> ids(List<Order> orders) => orders.map((o) => o.id).toList();

  group('按位置（默认）', () {
    test('外卖 → 电话外卖 → 桌子；桌子按桌号清单的顺序', () {
      final orders = [
        order(id: 't9', table: '9'),
        order(id: 'phone', type: OrderType.phonecallTakeaway, dailyNo: 1),
        order(id: 't2', table: '2'),
        order(id: 'take', type: OrderType.takeaway, dailyNo: 2),
        order(id: 'tA', table: 'A'),
      ];
      final out = sortInProgressOrders(
        orders,
        OrderSort.position,
        const ['1', '2', '3', '9', 'A', 'B'],
      );
      expect(ids(out), ['take', 'phone', 't2', 't9', 'tA']);
    });

    test('桌号**数字在字母前**，且按数值大小（1,2,9,10）', () {
      final orders = [
        order(id: 't10', table: '10'),
        order(id: 'tB', table: 'B'),
        order(id: 't9', table: '9'),
        order(id: 't1', table: '1'),
      ];
      final out = sortInProgressOrders(
        orders,
        OrderSort.position,
        const ['10', '9', 'B', '1'], // 清单里故意存成乱的
      );
      expect(ids(out), ['t1', 't9', 't10', 'tB']);
    });

    test('外卖之间按「当天第几号」排（#1 在 #2 前面）', () {
      final orders = [
        order(id: 'tk2', type: OrderType.takeaway, dailyNo: 2),
        order(id: 'tk1', type: OrderType.takeaway, dailyNo: 1),
        order(id: 'tk3', type: OrderType.takeaway, dailyNo: 3),
      ];
      final out =
          sortInProgressOrders(orders, OrderSort.position, const ['1', '2']);
      expect(ids(out), ['tk1', 'tk2', 'tk3']);
    });

    test('清单里没有的桌号：排在有号的桌子后面，按名字的自然顺序', () {
      final orders = [
        order(id: 'tVip', table: 'VIP'),
        order(id: 't2', table: '2'),
        order(id: 't11', table: '11'),
      ];
      final out = sortInProgressOrders(orders, OrderSort.position, const ['2']);
      expect(ids(out), ['t2', 't11', 'tVip'], reason: '11 是数字，排在 VIP 前面');
    });
  });

  group('按时间', () {
    test('最近动过的在最上面（用 updatedAt，不是 createdAt）', () {
      final old = order(id: 'old', table: '1', updated: 0);
      final mid = order(id: 'mid', table: '2', updated: 10);
      final fresh = order(id: 'fresh', table: '3', updated: 30);
      final out =
          sortInProgressOrders([old, fresh, mid], OrderSort.time, const []);
      expect(ids(out), ['fresh', 'mid', 'old']);
    });

    test('追单之后老单会冒到最上面（模拟：改单刷新了 updatedAt）', () {
      final a = order(id: 'a', table: '1', updated: 0);
      final b = order(id: 'b', table: '2', updated: 5);
      expect(ids(sortInProgressOrders([a, b], OrderSort.time, const [])),
          ['b', 'a']);
      // 给 a 加了个菜 → updatedAt 变成最新
      final a2 = a.copyWith(updatedAt: DateTime(2026, 10, 11, 13, 0));
      expect(ids(sortInProgressOrders([a2, b], OrderSort.time, const [])),
          ['a', 'b']);
    });
  });

  group('默认排序：按单号（从大到小）', () {
    test('进行中：号大的在最上面', () {
      final orders = [
        order(id: 'n2', table: '2', dailyNo: 2),
        order(id: 'n5', table: '3', dailyNo: 5),
        order(id: 'n1', table: '1', dailyNo: 1),
      ];
      expect(ids(sortInProgressOrders(orders, OrderSort.number, const [])),
          ['n5', 'n2', 'n1']);
    });

    test('跨天：**新的一天**排在旧的一天前面（号每天从 1 重新开始）', () {
      final orders = [
        order(
            id: '昨天#9',
            table: '1',
            dailyNo: 9,
            created: DateTime(2026, 10, 10, 20)),
        order(
            id: '今天#1',
            table: '2',
            dailyNo: 1,
            created: DateTime(2026, 10, 11, 9)),
      ];
      expect(ids(sortInProgressOrders(orders, OrderSort.number, const [])),
          ['今天#1', '昨天#9']);
    });

    test('老数据没有号（dailyNo = 0）排最后', () {
      final orders = [
        order(id: '老单', table: '1'),
        order(id: '新单', table: '2', dailyNo: 3),
      ];
      expect(ids(sortInProgressOrders(orders, OrderSort.number, const [])),
          ['新单', '老单']);
    });

    test('已结单也能按单号排（那也是它的默认排法）', () {
      final orders = [
        order(
            id: 'a', dailyNo: 3, total: 100, closed: DateTime(2026, 10, 11, 9)),
        order(
            id: 'b', dailyNo: 7, total: 20, closed: DateTime(2026, 10, 11, 10)),
        order(
            id: 'c', dailyNo: 5, total: 50, closed: DateTime(2026, 10, 11, 11)),
      ];
      expect(ids(sortClosedOrders(orders, ClosedSort.number)), ['b', 'c', 'a']);
    });
  });

  group('杂项', () {
    test('id 与枚举互转；认不出的当「按单号」（两个列表的默认）', () {
      expect(OrderSort.fromId('number'), OrderSort.number);
      expect(OrderSort.fromId('time'), OrderSort.time);
      expect(OrderSort.fromId('position'), OrderSort.position);
      expect(OrderSort.fromId('说什么呢'), OrderSort.number);
      expect(OrderSort.fromId(null), OrderSort.number);
    });

    test('两种排法都**不改**传进来的那个列表', () {
      final orders = [
        order(id: 'a', table: '5'),
        order(id: 'b', table: '1'),
      ];
      final copy = ids(orders);
      sortInProgressOrders(orders, OrderSort.position, const ['1', '5']);
      sortInProgressOrders(orders, OrderSort.time, const []);
      expect(ids(orders), copy);
    });

    test('位置完全一样的（同一张桌两张单）保持原先后（新的在上面）', () {
      final orders = [
        order(id: 'newer', table: '3'),
        order(id: 'older', table: '3'),
      ];
      final out =
          sortInProgressOrders(orders, OrderSort.position, const ['3']);
      expect(ids(out), ['newer', 'older']);
    });
  });

  group('已结单：按时间 / 按金额', () {
    test('按时间：**结账确认时间**由近到远（用 closedAt，不是 updatedAt）', () {
      final orders = [
        order(id: '早', closed: DateTime(2026, 10, 11, 9, 0), updated: 999),
        order(id: '晚', closed: DateTime(2026, 10, 11, 21, 0)),
        order(id: '中', closed: DateTime(2026, 10, 11, 15, 0)),
      ];
      expect(ids(sortClosedOrders(orders, ClosedSort.time)), ['晚', '中', '早']);
    });

    test('按时间：老数据没有 closedAt → 用开单时间算', () {
      final orders = [
        order(id: '新', created: DateTime(2026, 10, 12, 10, 0)),
        order(id: '旧', created: DateTime(2026, 10, 1, 10, 0)),
      ];
      expect(ids(sortClosedOrders(orders, ClosedSort.time)), ['新', '旧']);
    });

    test('按金额：**由大到小**', () {
      final orders = [
        order(id: '小', total: 35.5, closed: DateTime(2026, 10, 11, 9)),
        order(id: '大', total: 1200, closed: DateTime(2026, 10, 11, 10)),
        order(id: '中', total: 88.25, closed: DateTime(2026, 10, 11, 11)),
      ];
      expect(ids(sortClosedOrders(orders, ClosedSort.amount)),
          ['大', '中', '小']);
    });

    test('金额一样时：**最近结账的在前**；连时间也一样就保持原先后', () {
      final orders = [
        order(id: '同额-早', total: 100, closed: DateTime(2026, 10, 11, 9)),
        order(id: '同额-晚', total: 100, closed: DateTime(2026, 10, 11, 20)),
        order(id: '同额-同时-先', total: 100, closed: DateTime(2026, 10, 12, 9)),
        order(id: '同额-同时-后', total: 100, closed: DateTime(2026, 10, 12, 9)),
      ];
      expect(ids(sortClosedOrders(orders, ClosedSort.amount)),
          ['同额-同时-先', '同额-同时-后', '同额-晚', '同额-早']);
    });

    test('id 与枚举互转；认不出的当「按单号」（默认）', () {
      expect(ClosedSort.fromId('number'), ClosedSort.number);
      expect(ClosedSort.fromId('time'), ClosedSort.time);
      expect(ClosedSort.fromId('amount'), ClosedSort.amount);
      expect(ClosedSort.fromId('说什么呢'), ClosedSort.number);
      expect(ClosedSort.fromId(null), ClosedSort.number);
    });

    test('两种排法都**不改**传进来的那个列表', () {
      final orders = [
        order(id: 'a', total: 5, closed: DateTime(2026, 10, 11, 9)),
        order(id: 'b', total: 50, closed: DateTime(2026, 10, 11, 10)),
      ];
      final copy = ids(orders);
      sortClosedOrders(orders, ClosedSort.time);
      sortClosedOrders(orders, ClosedSort.amount);
      expect(ids(orders), copy);
    });
  });

  group('已结单：只看某一天', () {
    /// 10/1 中午、10/3 深夜 23:59、10/4 凌晨 00:01 各一单。
    List<Order> threeDays() => [
          order(id: '10-01', closed: DateTime(2026, 10, 1, 12, 0)),
          order(id: '10-03', closed: DateTime(2026, 10, 3, 23, 59)),
          order(id: '10-04', closed: DateTime(2026, 10, 4, 0, 1)),
        ];

    test('只留那一天，**23:59 结的也算当天**', () {
      expect(ids(filterOrdersOnDate(threeDays(), '2026-10-03')), ['10-03']);
    });

    test('零点过一分钟就归到第二天', () {
      expect(ids(filterOrdersOnDate(threeDays(), '2026-10-04')), ['10-04']);
    });

    test('那一天没有单 → 空（订单页会显示"还没有订单历史"）', () {
      expect(filterOrdersOnDate(threeDays(), '2026-11-01'), isEmpty);
    });

    test('传空字符串 = 不筛（全部），返回的是**新列表**不是同一个对象', () {
      final orders = threeDays();
      final out = filterOrdersOnDate(orders, '');
      expect(ids(out), ['10-01', '10-03', '10-04']);
      expect(identical(out, orders), isFalse);
    });

    test('老数据没有 closedAt → 按开单时间算', () {
      final orders = [
        order(id: '10-02', created: DateTime(2026, 10, 2, 20, 0)),
        order(id: '10-09', created: DateTime(2026, 10, 9, 20, 0)),
      ];
      expect(ids(filterOrdersOnDate(orders, '2026-10-02')), ['10-02']);
      expect(ids(filterOrdersOnDate(orders, '2026-10-09')), ['10-09']);
    });
  });

  group('进行中：现在固定**按单号从小到大**（排序开关已经去掉）', () {
    test('号小的在前；不同天的话旧的在前；没号的排最前', () {
      final orders = [
        order(id: 'no3', dailyNo: 3),
        order(id: 'none'), // 老数据没号
        order(id: 'no1', dailyNo: 1),
        order(id: 'no2', dailyNo: 2),
      ];
      expect(ids(sortOpenOrdersByNumber(orders)), ['none', 'no1', 'no2', 'no3']);
    });

    test('跨天：昨天那张排今天前面（先开先收）', () {
      final orders = [
        order(id: 'today', dailyNo: 1, created: DateTime(2026, 10, 12, 9, 0)),
        order(
          id: 'yesterday',
          dailyNo: 9,
          created: DateTime(2026, 10, 11, 21, 0),
        ),
      ];
      expect(ids(sortOpenOrdersByNumber(orders)), ['yesterday', 'today']);
    });

    test('号一样时按开单时间，顺序永远确定（不会乱跳）', () {
      final orders = [
        order(id: 'b', dailyNo: 5, created: DateTime(2026, 10, 12, 9, 30)),
        order(id: 'a', dailyNo: 5, created: DateTime(2026, 10, 12, 9, 0)),
      ];
      expect(ids(sortOpenOrdersByNumber(orders)), ['a', 'b']);
      // 传进去的顺序反过来，结果不变
      expect(ids(sortOpenOrdersByNumber(orders.reversed.toList())), ['a', 'b']);
    });
  });
}
