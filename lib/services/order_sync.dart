import '../models/order.dart';

/// 后台同步要用的一行（服务器上的 `orders` 表）。
///
/// 服务器还会自己维护 `rev` / `updated_at`（触发器），App 只管送 `payload`。
class RemoteOrder {
  /// 单号。
  final String id;
  final String status;
  final int rev;
  final DateTime updatedAt;

  /// 服务器上存的整张单（`Order.toJson()` 的形状）。
  final Map<String, dynamic> payload;

  const RemoteOrder({
    required this.id,
    required this.status,
    required this.rev,
    required this.updatedAt,
    required this.payload,
  });

  /// 从 PostgREST 返回的一行 JSON 里读出来。
  ///
  /// 注意 `data` 用 `is Map` 判断而不是 `as Map?` ——
  /// 服务器上那一列要是被谁写成了别的形状（数组 / 字符串），
  /// 直接强转会在**拉取**的时候就抛类型错误，把整个同步搞挂。
  /// 这里读不出来就给个空 map，后面的解析会把它当作「坏数据」跳过。
  factory RemoteOrder.fromRow(Map<String, dynamic> row) => RemoteOrder(
        id: (row['id'] ?? '').toString(),
        status: (row['status'] ?? 'in_progress').toString(),
        rev: (row['rev'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        payload: row['data'] is Map
            ? (row['data'] as Map).cast<String, dynamic>()
            : <String, dynamic>{},
      );
}

/// **同步的纯逻辑**（不碰网络、不碰界面 → 好写单测）。
///
/// 规则（尽量简单，够用就行）：
/// - **服务器是权威**：`rev` 大的一方更新；`rev` 一样就比 `updatedAt`；
///   还一样就比设备名（保证两台设备算出同一个结果，不会来回抖）。
/// - **本地还没推上去的**（`rev == 0` 或 `dirty`）→ 推。
/// - **服务器上有的、本地没有的** → 拉下来。
/// - **两边都有** → 谁新听谁的。
class OrderSync {
  const OrderSync._();

  /// 谁更新？[a] 比 [b] 新就返回 true。
  static bool isNewer(Order a, Order b) {
    if (a.rev != b.rev) return a.rev > b.rev;
    final at = a.updatedAt.millisecondsSinceEpoch;
    final bt = b.updatedAt.millisecondsSinceEpoch;
    if (at != bt) return at > bt;
    return a.deviceId.compareTo(b.deviceId) > 0;
  }

  /// 本地哪些单**要推**给后台：
  /// 有未推送改动的（`dirty`）、本地版本比服务器新的、或者**从没推过**的（`rev == 0`）。
  ///
  /// ⚠️ [remote] **可能只是「增量窗口」里的那几行**（同步时只拉 `updated_at > 水位线`
  /// 的改动，不是每次都拉全表）。所以这里**不能**把「[remote] 里没有」当成
  /// 「服务器上没有」—— 只有 `rev == 0`（确定没推过）或本地脏才推，
  /// 否则每 25 秒都会把全部历史单重推一遍。
  static List<Order> chooseOutgoing(
    List<Order> local,
    Map<String, RemoteOrder> remote,
  ) {
    final out = <Order>[];
    for (final o in local) {
      final r = remote[o.id];
      if (r == null) {
        // 窗口里没有：没推过的（rev==0）或者本地脏的 → 推
        if (o.rev == 0 || o.dirty) out.add(o);
        continue;
      }
      if (o.dirty) {
        out.add(o); // 本地有改动没推上去 → 推
        continue;
      }
      // 本地版本更新（例如离线期间改了，另一个设备也改了）→ 推本地
      if (o.rev > r.rev) out.add(o);
    }
    return out;
  }

  /// 服务器上哪些单**要拉下来**（本地没有，或服务器版本更新）。
  ///
  /// 服务器上那一行如果**数据不完整**（比如 `data` 里少了 `id` / `lines`，
  /// 或者被别的东西改成别的形状），解析会抛类型错误 —— 这里**跳过那一行**
  /// （并且通过 [onBadRow] 报给调用方，好让它提醒用户 / 打日志），
  /// 不让一张坏数据把整个同步永远搞失败。
  static List<Order> chooseIncoming(
    List<Order> local,
    Map<String, RemoteOrder> remote, {
    void Function(RemoteOrder bad)? onBadRow,
  }) {
    final byId = <String, Order>{for (final o in local) o.id: o};
    final out = <Order>[];
    for (final r in remote.values) {
      final mine = byId[r.id];
      // 要不要用服务器这份？（本地没有 / 服务器版本更高 / 同版本但时间更新且本地不脏）
      final newer = mine == null ||
          mine.rev < r.rev ||
          (mine.rev == r.rev &&
              r.updatedAt.isAfter(mine.updatedAt) &&
              !mine.dirty);
      if (!newer) continue;
      final o = tryOrderFromRemote(r);
      if (o == null) {
        onBadRow?.call(r);
        continue;
      }
      out.add(o);
    }
    return out;
  }

  /// 下一次**增量拉取**的「水位线」（纯函数，好测）。
  ///
  /// 规则：**只用数据自己带的时间**（服务器写的 `updated_at`）来推进水位线。
  ///
  /// 为什么不用「响应头里的服务器时间」：响应头是在查询**之后**生成的，
  /// 比查询那一刻晚（网络慢的时候可能晚好几秒）。用它当水位线，就可能跳过
  /// 「查询期间刚提交、`updated_at` 又比响应头早」的行 —— 那些行要等下次重启
  /// 全量拉取才会回来。用数据时间就没这个洞：能拉到的行一定在「查询那一刻」之前
  /// 就提交了，所以比水位线新的行（哪怕正好在这趟查询期间提交）下一趟必然满足
  /// `updated_at > 水位线`，一行都不会漏。
  ///
  /// - 取 [rowTimes] 里**最大**的那个；
  /// - [serverTime]（响应头的服务器时间）只当**上限兜底**：万一某行的时间戳被写到
  ///   了未来，水位线也不会跟着跳过头、把后面的行全漏掉；
  /// - 再往前退 [overlap] 做重叠（重复拉到的行是幂等的，合并规则会处理）；
  /// - **一行都没拉到就不推进**（宁可每趟多查一次空窗口，也不能漏行）。
  static DateTime? nextWatermark({
    DateTime? serverTime,
    Iterable<DateTime> rowTimes = const [],
    Duration overlap = const Duration(seconds: 5),
  }) {
    DateTime? best;
    for (final t in rowTimes) {
      final u = t.toUtc();
      if (best == null || u.isAfter(best)) best = u;
    }
    if (best == null) return null; // 没拉到任何行 → 水位线不动
    final cap = serverTime?.toUtc();
    if (cap != null && best.isAfter(cap)) best = cap;
    return best.subtract(overlap);
  }

  /// 把服务器一行还原成 [Order]（rev/updatedAt 用服务器那份，dirty = false）。
  static Order _orderFromRemote(RemoteOrder r) {
    final o = Order.fromJson(r.payload);
    return o.copyWith(rev: r.rev, updatedAt: r.updatedAt, dirty: false);
  }

  /// 跟 [_orderFromRemote] 一样，但**坏数据返回 null 而不是抛异常**。
  ///
  /// 为什么要有它：服务器上的 `data` 里只要少一个必填字段
  /// （`Order.fromJson` 里是 `json['id'] as String` 这种强转），
  /// 就会抛 `type 'NULL' is not a subtype of type 'String' in type cast`，
  /// 而调用方如果没兜住，就会**按一次「立即同步」报一次错**，一张单都同步不了。
  /// 真实踩过这个坑，所以坏行跳过、其余的照常同步。
  static Order? tryOrderFromRemote(RemoteOrder r) {
    try {
      return _orderFromRemote(r);
    } catch (_) {
      return null;
    }
  }

  /// 把一张单变成「往服务器送的一行」（列 + JSON）。
  ///
  /// 服务器会自己覆盖 `rev` / `updated_at`，所以这里不用送它们；
  /// 送 `rev` 只是为了「乐观并发」时的参考，服务器不采信。
  static Map<String, dynamic> toRow(Order o, {required String deviceId}) => {
        'id': o.id,
        'status': o.status.id,
        'order_type': o.orderType.id,
        'table_no': o.table,
        'total': o.total,
        'item_count': o.itemCount,
        'cashier': o.cashier,
        'device_id': deviceId.isEmpty ? o.deviceId : deviceId,
        'closed_at': o.closedAt?.toIso8601String(),
        // 整张单原样存进 data（后台网页直接读它）
        'data': o.copyWith(dirty: false, deviceId: deviceId).toJson(),
      };

  /// 结账时要并进服务器 JSON 的那份「补丁」= **本地整张单的 JSON**。
  ///
  /// ⚠️ 这里**故意送整份**，而不是只挑「结账相关」的几个字段 —— 因为有一类很容易
  /// 撞上的丢数据场景：
  ///
  ///   1. 14:00 点了一单（推上去了，rev=1）；
  ///   2. 14:05 又加了一道菜（本地 `dirty`，还没推上去）；
  ///   3. 14:06 客人结账 → 走 `close_order()`。
  ///
  /// 如果补丁里只有结账字段，服务器就是拿**它自己那份旧数据**（少一道菜）来合并，
  /// 结完账我们再把服务器那份采纳回来 → **新加的那道菜在小票和后台里凭空消失**。
  /// 送整份 JSON 就没这个问题：`data = data || p_patch` 会把整张单覆盖成本地这份，
  /// 同时 CAS（`status <> 'completed'`）照样保证「只结成功一次」。
  static Map<String, dynamic> closePatch(
    Order closed, {
    required String deviceId,
  }) =>
      closed.copyWith(dirty: false, deviceId: deviceId).toJson();
}
