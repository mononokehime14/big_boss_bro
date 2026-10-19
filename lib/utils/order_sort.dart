import '../models/order.dart';
import 'format.dart'; // dayKey()：按「本机日历日」筛日期范围
import 'menu_sort.dart'; // sortedTables()：桌号的自然顺序（数字在字母前）

/// 日结 / 列表里算「这是哪一天的单」用的时间：结过账就用**结账确认时间**，
/// 老数据（没有 `closedAt`）用开单时间。
DateTime closedOrCreatedAt(Order o) => o.closedAt ?? o.createdAt;

/// 「进行中」的订单列表怎么排（订单页那个小开关）。
enum OrderSort {
  /// **默认 = 按单号**：**单号从大到小**（号大的 = 更近开的单，在最上面）。
  ///
  /// 单号是"每天从 1 开始"的那个号（`Order.dailyNo`，堂食 / 外卖 / 电话外卖**共用**一条序列，
  /// 见 `PosController._nextDailyNo`）。注意号**每天归零**，所以排序时先按**哪一天**
  /// （新的一天在上面），同一天之内再按号从大到小。
  number('number'),

  /// **按位置**：**外卖 → 电话外卖 → 桌子**，
  /// 桌子按桌号清单的顺序（`1 2 … 9 10 A B C`，跟点单页那个下拉一致）。
  position('position'),

  /// **按时间**：最近**保存 / 下厨房**的排最上面（`Order.updatedAt`：
  /// 每次追单、改份数、改备注都会刷新，所以"刚动过的那张"永远在最上面）。
  time('time');

  final String id;
  const OrderSort(this.id);

  static OrderSort fromId(String? id) => OrderSort.values.firstWhere(
        (e) => e.id == id,
        orElse: () => OrderSort.number,
      );
}

/// 按 [sort] 排「进行中」的订单（返回新列表，不动传进来的那个）。
///
/// [tables] 是设置里的桌号清单（只影响 [OrderSort.position] 的先后）。
List<Order> sortInProgressOrders(
  List<Order> orders,
  OrderSort sort,
  List<String> tables,
) {
  switch (sort) {
    case OrderSort.number:
      return _byNumber(orders);
    case OrderSort.position:
      return _byPosition(orders, tables);
    case OrderSort.time:
      return _byTime(orders);
  }
}

/// **「进行中」现在的固定排法：按单号从小到大**。
///
/// 订单页那一排"排序方式"已经去掉了（实际没用）：进行中永远是**号小的在前**，
/// 也就是**先开的单排在上面** —— 收银员顺着往下收，不会漏老单。
///
/// 单号每天从 1 开始，所以先按"哪一天"（旧的在前），同一天里号小的在前；
/// 老数据没号（`0`）的排最前。同号用开单时间兜底，顺序永远确定。
List<Order> sortOpenOrdersByNumber(List<Order> orders) => _sortBy(
      orders,
      (o) => <num>[
        _dayNumber(o),
        o.dailyNo > 0 ? o.dailyNo : 0,
        o.createdAt.millisecondsSinceEpoch,
      ],
    );

/// **「已结单」列表怎么排**（订单页「已结单」那一页的小开关）。
enum ClosedSort {
  /// **默认 = 按单号**：单号从大到小（跟「进行中」的默认排序同一个规则：
  /// 先看哪一天，同一天里号大的在前）。
  number('number'),

  /// **按时间**：**结账确认时间由近到远**（今天结的最上面）。
  /// 用 `closedAt`（结账那一刻），老数据没有就用开单时间。
  time('time'),

  /// **按金额**：金额由大到小（对账时一眼看到大单）。
  amount('amount');

  final String id;
  const ClosedSort(this.id);

  static ClosedSort fromId(String? id) => ClosedSort.values.firstWhere(
        (e) => e.id == id,
        orElse: () => ClosedSort.number,
      );
}

/// 按 [sort] 排「已结单」（返回新列表，不动传进来的那个）。
List<Order> sortClosedOrders(List<Order> orders, ClosedSort sort) {
  switch (sort) {
    case ClosedSort.number:
      return _byNumber(orders);
    case ClosedSort.time:
      return _sortBy(orders, (o) => <num>[-_closedMs(o)]);
    case ClosedSort.amount:
      // 金额一样时，**最近结账的在前**（对账时好找）
      return _sortBy(orders, (o) => <num>[-o.total, -_closedMs(o)]);
  }
}

/// 「已结单」只看**某一天**（`yyyy-MM-dd`）—— 跟「日结」用的是同一套「哪一天」。
///
/// 比的是**本机日历日**（`utils/format.dart` 的 `dayKey`）：结了账用**结账确认时间**，
/// 老数据没有就用开单时间。传空字符串 = 不筛（全部）。
List<Order> filterOrdersOnDate(List<Order> orders, String dateKey) {
  if (dateKey.isEmpty) return List.of(orders);
  return orders.where((o) => dayKey(closedOrCreatedAt(o)) == dateKey).toList();
}

int _closedMs(Order o) => closedOrCreatedAt(o).millisecondsSinceEpoch;

/// **按单号排（默认）**：**号大的在前**（更近开的单在上面）。
///
/// 单号每天从 1 开始，所以**先按"哪一天"排**（新的一天在上面），
/// 同一天里再按号从大到小；老数据没号（`0`）的排到最后。
/// 最后一级用开单时间兜底，保证同号的顺序也是确定的。
///
/// ⚠️ `_sortBy` 排的是**升序**，要"从大到小"就得**把键取负** ——
/// 这里所有的键都是负数（`-天`、`-号`、`-毫秒`）。
/// 没号的单特殊：真号取负之后都是负数，所以给它 `0`（比任何真号都大 → 排最后）。
List<Order> _byNumber(List<Order> orders) => _sortBy(orders, (o) => <num>[
      -_dayNumber(o),
      o.dailyNo > 0 ? -o.dailyNo : 0,
      -o.createdAt.millisecondsSinceEpoch,
    ]);

/// 开单那天写成一个能比大小的整数（`20261011`），**越新越大**。
int _dayNumber(Order o) =>
    o.createdAt.year * 10000 + o.createdAt.month * 100 + o.createdAt.day;

/// 按位置排：外卖（0）→ 电话外卖（1）→ 平台外卖（2）→ 桌子（3）。
///
/// 组内：
/// - 外卖 / 电话外卖 / 平台外卖 → 按「当天第几号」（`#1 #2 …`；老数据没号的排最后）；
/// - 桌子 → 按桌号在清单里的位置（**清单里没有的桌号**排到最后，按名字的自然顺序）。
///
/// 位置完全一样的（同一张桌开了两张单）→ **保持原来的先后**（新的在上面）。
List<Order> _byPosition(List<Order> orders, List<String> tables) {
  // 桌号顺序 = 设置里的桌号清单 + 单子上出现、但清单里没有的桌号（排最后）
  final extra = <String>[];
  for (final o in orders) {
    if (o.isTakeaway) continue;
    final t = o.table.trim();
    if (t.isEmpty || tables.contains(t) || extra.contains(t)) continue;
    extra.add(t);
  }
  final all = sortedTables(<String>[...tables, ...extra]);
  final rank = <String, int>{for (var i = 0; i < all.length; i++) all[i]: i};

  return _sortBy(orders, (o) => <int>[
        o.isPhoneTakeaway
            ? 1
            : (o.isPlatformTakeaway ? 2 : (o.isTakeaway ? 0 : 3)),
        o.isTakeaway
            ? (o.dailyNo > 0 ? o.dailyNo : 999999)
            : (rank[o.table.trim()] ?? 999999),
      ]);
}

/// 按时间排：**最近动过的在上面**。
///
/// 用 `updatedAt`（不是 `createdAt`）：一张老单刚加了菜 / 刚下厨房，也该冒到最上面
/// —— 收银员要找的正是"我刚动过的那张"。
List<Order> _byTime(List<Order> orders) => _sortBy(
      orders,
      (o) => <num>[-o.updatedAt.millisecondsSinceEpoch],
    );

/// 按「键」排序；键一样时**保持原来的先后**。
///
/// 为什么要自己写：Dart 的 `List.sort` **不稳定**，同一个位置的几张单会乱跳；
/// 这里把原下标当最后一级键，结果就永远是确定的。
///
/// 键是 `num`（int / double 都能用）：**按金额排**要用小数。
List<Order> _sortBy(List<Order> orders, List<num> Function(Order) keyOf) {
  final items = <({Order order, List<num> key, int index})>[
    for (var i = 0; i < orders.length; i++)
      (order: orders[i], key: keyOf(orders[i]), index: i),
  ];
  items.sort((a, b) {
    final n = a.key.length < b.key.length ? a.key.length : b.key.length;
    for (var i = 0; i < n; i++) {
      final c = a.key[i].compareTo(b.key[i]);
      if (c != 0) return c;
    }
    return a.index.compareTo(b.index);
  });
  return items.map((e) => e.order).toList();
}
