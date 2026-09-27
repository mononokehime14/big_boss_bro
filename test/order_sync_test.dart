import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/order_sync.dart';

/// 后台同步的**纯逻辑**：谁推、谁拉、谁赢。
/// 这里不联网，只盯规则 —— 规则错了比网络错更可怕（会丢单、会重复结账）。
void main() {
  Order order({
    required String id,
    int rev = 0,
    bool dirty = true,
    String deviceId = 'A',
    DateTime? updatedAt,
    OrderStatus status = OrderStatus.inProgress,
    double total = 28,
  }) =>
      Order(
        id: id,
        createdAt: DateTime(2026, 9, 20, 12),
        lines: const [OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28)],
        total: total,
        status: status,
        deviceId: deviceId,
        rev: rev,
        dirty: dirty,
        updatedAt: updatedAt ?? DateTime(2026, 9, 20, 12),
      );

  RemoteOrder remote({
    required String id,
    int rev = 1,
    DateTime? updatedAt,
    OrderStatus status = OrderStatus.inProgress,
  }) =>
      RemoteOrder(
        id: id,
        status: status.id,
        rev: rev,
        updatedAt: updatedAt ?? DateTime(2026, 9, 20, 12, 5),
        payload: order(id: id, rev: rev, dirty: false, status: status).toJson(),
      );

  group('谁更新 isNewer', () {
    test('rev 大的赢', () {
      expect(OrderSync.isNewer(order(id: 'a', rev: 3), order(id: 'a', rev: 2)),
          isTrue);
      expect(OrderSync.isNewer(order(id: 'a', rev: 2), order(id: 'a', rev: 3)),
          isFalse);
    });

    test('rev 一样就比时间', () {
      expect(
        OrderSync.isNewer(
          order(id: 'a', rev: 2, updatedAt: DateTime(2026, 9, 20, 13)),
          order(id: 'a', rev: 2, updatedAt: DateTime(2026, 9, 20, 12)),
        ),
        isTrue,
      );
    });

    test('完全一样时按设备名定胜负（两台设备算出同一个结果）', () {
      final a = order(id: 'a', rev: 2, deviceId: 'A');
      final b = order(id: 'a', rev: 2, deviceId: 'B');
      expect(OrderSync.isNewer(b, a), isTrue);
      expect(OrderSync.isNewer(a, b), isFalse);
    });
  });

  group('推哪些 chooseOutgoing', () {
    test('服务器没有的 → 推', () {
      final out = OrderSync.chooseOutgoing([order(id: 'n1')], {});
      expect(out.map((o) => o.id), ['n1']);
    });

    test('本地有未推送的改动（dirty）→ 推', () {
      final out = OrderSync.chooseOutgoing(
        [order(id: 'n1', rev: 5, dirty: true)],
        {'n1': remote(id: 'n1', rev: 5)},
      );
      expect(out.map((o) => o.id), ['n1']);
    });

    test('本地版本更高 → 推；一样或更低且不脏 → 不推', () {
      expect(
        OrderSync.chooseOutgoing(
          [order(id: 'n1', rev: 6, dirty: false)],
          {'n1': remote(id: 'n1', rev: 5)},
        ).length,
        1,
      );
      expect(
        OrderSync.chooseOutgoing(
          [order(id: 'n1', rev: 5, dirty: false)],
          {'n1': remote(id: 'n1', rev: 5)},
        ),
        isEmpty,
      );
      expect(
        OrderSync.chooseOutgoing(
          [order(id: 'n1', rev: 4, dirty: false)],
          {'n1': remote(id: 'n1', rev: 5)},
        ),
        isEmpty,
      );
    });

    test('增量窗口里没有、但已经推过（rev>0）也不脏 → **不重推**', () {
      // 增量同步只拉「水位线之后改过的行」，所以 remote 里没有 ≠ 服务器上没有。
      // 这里如果重推，就会每 25 秒把全部历史单再上传一遍。
      final out = OrderSync.chooseOutgoing(
        [order(id: 'n1', rev: 7, dirty: false)],
        const {},
      );
      expect(out, isEmpty);
      // 而「从没推过」（rev=0）的一定要推
      expect(
        OrderSync.chooseOutgoing([order(id: 'n2', rev: 0, dirty: false)], const {})
            .map((o) => o.id),
        ['n2'],
      );
    });
  });

  group('增量拉取的水位线 nextWatermark', () {
    test('以拉回来的行里最大的 updated_at 为准，再往前退 5 秒做重叠', () {
      final w = OrderSync.nextWatermark(
        serverTime: DateTime.utc(2026, 9, 20, 12, 0, 0),
        rowTimes: [
          DateTime.utc(2026, 9, 20, 11, 59, 0),
          DateTime.utc(2026, 9, 20, 11, 58, 30),
        ],
      );
      // 用**行的时间**（11:59:00）而不是响应头时间（12:00:00）：
      // 响应头比查询晚，用它会让「查询期间刚提交的行」被跳过。
      expect(w, DateTime.utc(2026, 9, 20, 11, 58, 55));
    });

    test('行的时间比响应头还新（被写到未来）时，以响应头为上限', () {
      final w = OrderSync.nextWatermark(
        serverTime: DateTime.utc(2026, 9, 20, 12, 0, 0),
        rowTimes: [DateTime.utc(2026, 9, 20, 23, 0, 0)],
      );
      expect(w, DateTime.utc(2026, 9, 20, 11, 59, 55),
          reason: '水位线跳过头会把后面的行全漏掉');
    });

    test('一行都没拉到 → null（水位线不动，宁可不前进也不能漏行）', () {
      expect(OrderSync.nextWatermark(), isNull);
      expect(
        OrderSync.nextWatermark(serverTime: DateTime.utc(2026, 9, 20, 12)),
        isNull,
        reason: '只有响应头时间、没有数据 → 不推进',
      );
    });
  });

  group('拉哪些 chooseIncoming', () {
    test('本地没有的 → 拉下来，并且 dirty=false', () {
      final out = OrderSync.chooseIncoming([], {'n9': remote(id: 'n9')});
      expect(out.length, 1);
      expect(out.first.id, 'n9');
      expect(out.first.dirty, isFalse, reason: '从服务器拉的不用再推回去');
      expect(out.first.rev, 1);
      expect(out.first.updatedAt, DateTime(2026, 9, 20, 12, 5));
    });

    test('服务器版本更高 → 覆盖本地', () {
      final out = OrderSync.chooseIncoming(
        [order(id: 'n1', rev: 2, dirty: false)],
        {'n1': remote(id: 'n1', rev: 3)},
      );
      expect(out.map((o) => o.id), ['n1']);
      expect(out.first.rev, 3);
    });

    test('本地更新 / 本地有未推送改动 → 先不拉（避免把本地改动冲掉）', () {
      expect(
        OrderSync.chooseIncoming(
          [order(id: 'n1', rev: 4, dirty: false)],
          {'n1': remote(id: 'n1', rev: 3)},
        ),
        isEmpty,
      );
      expect(
        OrderSync.chooseIncoming(
          [order(id: 'n1', rev: 3, dirty: true)],
          {'n1': remote(id: 'n1', rev: 3)},
        ),
        isEmpty,
      );
    });

    test('结账后的单也能拉回来（状态是已结账）', () {
      final out = OrderSync.chooseIncoming(
        [],
        {'n1': remote(id: 'n1', rev: 4, status: OrderStatus.completed)},
      );
      expect(out.first.status, OrderStatus.completed);
      expect(out.first.isInProgress, isFalse);
    });

    test('服务器上那一行数据不完整 → **跳过它**，不让整趟同步失败', () {
      // 真实踩过的坑：服务器上有一行 data 少了必填字段，
      // Order.fromJson 里的 `json['id'] as String` 会抛
      // 「type 'NULL' is not a subtype of type 'String' in type cast」，
      // 一按「立即同步」就报错，一张单都同步不了。
      final broken = RemoteOrder(
        id: 'bad-1',
        status: 'in_progress',
        rev: 2,
        updatedAt: DateTime(2026, 9, 20, 12, 5),
        payload: const {'id': 'bad-1'}, // 没有 createdAt / lines
      );
      final out = OrderSync.chooseIncoming(
        [],
        {
          'bad-1': broken,
          'n9': remote(id: 'n9'),
        },
      );
      expect(out.map((o) => o.id), ['n9'], reason: '坏的跳过，好的照拉');
      expect(OrderSync.tryOrderFromRemote(broken), isNull);
    });
  });

  group('往服务器送的行 toRow', () {
    test('列 + 整张单的 JSON 都在，dirty 会被清掉', () {
      final o = order(id: 'n1', rev: 0, dirty: true, deviceId: '');
      final row = OrderSync.toRow(o, deviceId: '收银台A');

      expect(row['id'], 'n1');
      expect(row['status'], 'in_progress');
      expect(row['order_type'], 'dine_in');
      expect(row['total'], 28);
      expect(row['item_count'], 1);
      expect(row['device_id'], '收银台A');
      final data = row['data'] as Map<String, dynamic>;
      expect(data['id'], 'n1');
      expect(data['dirty'], isFalse, reason: '送到服务器的那份不要带本地脏标记');
      expect(data['deviceId'], '收银台A');
    });

    test('外卖 / 电话外卖的类型也会送对', () {
      final t = order(id: 't1').copyWith(orderType: OrderType.takeaway);
      final p = order(id: 'p1').copyWith(orderType: OrderType.phonecallTakeaway);
      expect(OrderSync.toRow(t, deviceId: 'A')['order_type'], 'takeaway');
      expect(OrderSync.toRow(p, deviceId: 'A')['order_type'],
          'phonecall_takeaway');
    });
  });

  group('结账补丁 closePatch', () {
    test('送的是**整份本地数据**：结账字段 + 菜的明细都在', () {
      final closed = order(
        id: 'n1',
        status: OrderStatus.completed,
        total: 30,
      ).copyWith(
        paymentMethod: PaymentMethod.cash,
        receivedAmount: 50,
        changeAmount: 20,
        closedAt: DateTime(2026, 9, 20, 13),
      );
      final patch = OrderSync.closePatch(closed, deviceId: '收银台A');

      expect(patch['status'], 'completed');
      expect(patch['paymentMethod'], 'cash');
      expect(patch['receivedAmount'], 50);
      expect(patch['changeAmount'], 20);
      expect(patch['total'], 30);
      expect(patch['deviceId'], '收银台A');
      expect(patch['dirty'], isFalse, reason: '送上去的那份不带本地脏标记');
      // 关键：菜的明细必须带上 —— 只送结账字段的话，
      // 「推上去之后又加了菜、然后马上结账」会把新加的菜丢掉。
      expect(patch['lines'], isA<List>());
      expect((patch['lines'] as List).length, 1);
    });
  });

  group('本地 JSON 往返（同步字段要存得住）', () {
    test('rev / updatedAt / deviceId / dirty 能存能读', () {
      final o = order(
        id: 'n1',
        rev: 7,
        dirty: false,
        deviceId: '平板B',
        updatedAt: DateTime(2026, 9, 20, 14, 30),
      );
      final back = Order.fromJson(o.toJson());
      expect(back.rev, 7);
      expect(back.deviceId, '平板B');
      expect(back.dirty, isFalse);
      expect(back.updatedAt, DateTime(2026, 9, 20, 14, 30));
    });

    test('老数据（没有这些字段）默认 rev=0 + dirty=true → 第一次同步会推上去', () {
      final legacy = {
        'id': 'old-1',
        'createdAt': '2026-01-01T12:00:00.000',
        'lines': [
          {'name': '牛肉炒饭', 'quantity': 1, 'unitPrice': 28},
        ],
        'total': 28.0,
        'paymentMethod': 'cash',
        'status': 'completed',
      };
      final o = Order.fromJson(legacy);
      expect(o.rev, 0);
      expect(o.dirty, isTrue);
      expect(o.updatedAt, DateTime(2026, 1, 1, 12));
      expect(o.deviceId, '');
    });

    test('touch() 会刷新时间 + 标脏', () {
      final before = order(
        id: 'n1',
        rev: 3,
        dirty: false,
        deviceId: 'A',
        updatedAt: DateTime(2020, 1, 1), // 用一个过去的固定时间，好比较
      );
      final o = before.touch(deviceId: 'B');
      expect(o.dirty, isTrue);
      expect(o.deviceId, 'B');
      expect(o.rev, 3, reason: 'rev 是服务器的，touch 不动它');
      expect(o.updatedAt.isAfter(DateTime(2020, 1, 1)), isTrue);
    });
  });
}
