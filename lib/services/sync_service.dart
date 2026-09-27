import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:http/http.dart' as http;

import '../data/menu_store.dart';
import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import 'order_sync.dart';
import 'supabase_rest.dart';

/// 同步状态（设置页显示用）。
class SyncStatus {
  /// 正在同步。
  final bool busy;

  /// 上次同步成功的时间（null = 还没成功过）。
  final DateTime? lastSyncAt;

  /// 上次错误（null = 一切正常）。
  final String? error;

  /// 还有几张单没推上去（界面上显示「待上传 N 张」）。
  final int pendingOrders;

  /// 上次同步推上去几张、拉下来几张（给用户一点反馈）。
  final int pushed;
  final int pulled;

  const SyncStatus({
    this.busy = false,
    this.lastSyncAt,
    this.error,
    this.pendingOrders = 0,
    this.pushed = 0,
    this.pulled = 0,
  });
}

/// **后台同步**：把本机的单子和菜单同步到 Supabase（云端），
/// 让多台设备共用一个「单池」、老板在后台网页看得到。
///
/// 几条铁律（都很重要）：
/// 1. **本地优先**：点单/打单/结账永远先写本机，这个服务只是「后台异步搬运」；
/// 2. **失败绝不上抛**：任何网络/登录错误都只记到 [status].error，收银照常；
/// 3. **顺序是「拉 → 合并 → 推」**：先把别人的改动拿回来合上，再推自己脏的数据，
///    这样不会用旧数据盖掉别人刚结的单；
/// 4. **结账走 `close_order()` 的 CAS**：服务器上「进行中 → 已结账」只成功一次，
///    另一台设备拿到的是「已结账」的现状，采纳即可，不会重复算钱；
/// 5. **拉取是增量的**（`updated_at > 水位线` + 翻页），App 启动后第一趟做全量；
/// 6. **每趟对账一次「进行中」的单**：别人删掉的，本地跟着删（不然会一直挂在屏幕上）。
class SyncService extends ChangeNotifier {
  final PosController pos;
  final SettingsController settingsCtl;

  /// 只有测试会传自己的 http client。
  final http.Client? httpClient;

  SupabaseRest? _rest;
  Timer? _timer;
  bool _started = false;

  /// **增量拉取的水位线**：下次只拉 `updated_at > 它` 的行。
  ///
  /// 值来自**服务器写的 `updated_at`**（不是响应头时间、更不是本机时钟）——
  /// 这样一行都不会漏，详见 [OrderSync.nextWatermark] 的注释。
  ///
  /// 只存在内存里：App 重启后第一趟做一次全量（顺便把别人删掉的单对账掉），
  /// 之后就一直增量 —— 这样不用管「换过后台项目 / 本机时钟跳变」这些坑。
  String? _since;

  /// 一次拉多少行（Supabase 的接口单次最多给 1000 行，所以必须翻页）。
  /// 测试里会调小来验证翻页逻辑。
  final int pageSize;

  /// 一趟同步最多拉多少行（保险丝：历史单特别多时别把这一趟拖太久/占太多内存，
  /// 剩下的下一趟接着拉 —— 水位线是按数据推进的，所以不会卡住也不会漏）。
  static const int maxPullRows = 10000;

  /// 这一趟跳过了几张「服务器上数据不完整」的单（正常 0）。
  /// 不为 0 时会在状态里提醒一句（不是失败：其它单照常同步）。
  int _skippedBadRows = 0;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  /// 正在同步（界面按钮用它变灰）。
  bool get busy => _status.busy;

  /// 同步间隔（前台每 [interval] 拉一次别人的改动）。
  static const Duration interval = Duration(seconds: 25);

  SyncService({
    required this.pos,
    required this.settingsCtl,
    this.httpClient,
    this.pageSize = 1000,
  });

  Settings get _settings => settingsCtl.settings;

  /// 配置齐了吗（地址 + key + 账号）。
  bool get isConfigured =>
      _settings.supabaseUrl.trim().isNotEmpty &&
      _settings.supabaseAnonKey.trim().isNotEmpty &&
      _settings.syncEmail.trim().isNotEmpty;

  /// **现在为什么同步不了**：返回一句文案的 key（设置页直接用 `L10n.t()` 显示），
  /// 一切正常返回 null。
  ///
  /// 为什么要有它：`syncNow()` 在「开关没开 / 没填全」的时候是**静默返回**的 ——
  /// 点「立即同步」会看到状态数字没变（像「同步成功但 0 张」），
  /// 让人以为数据上去了，其实一个请求都没发。真实踩过这个坑，所以要让界面能说清楚。
  String? get syncBlockedReason {
    if (!_settings.syncEnabled) return 'sync.blockedDisabled';
    if (_settings.supabaseUrl.trim().isEmpty) return 'sync.blockedUrl';
    if (_settings.supabaseAnonKey.trim().isEmpty) return 'sync.blockedKey';
    if (_settings.syncEmail.trim().isEmpty) return 'sync.blockedEmail';
    if (_settings.syncPassword.isEmpty) return 'sync.blockedPassword';
    return null;
  }

  /// 这台设备的名字（没填就写「未命名设备」）。
  String get deviceName =>
      _settings.deviceName.trim().isEmpty ? '未命名设备' : _settings.deviceName.trim();

  SupabaseRest? get _client {
    if (!isConfigured) return null;
    final rest = _rest;
    if (rest != null &&
        // 用 SupabaseRest 里那套整理规则（同一个规则，不然会每趟都重建客户端、
        // 把登录态丢掉 → 每次同步都要重新登录）
        rest.url == SupabaseRest.normalizeUrl(_settings.supabaseUrl) &&
        rest.anonKey == _settings.supabaseAnonKey.trim()) {
      return rest;
    }
    // 地址/账号改了 → 重建客户端
    rest?.close();
    final made = SupabaseRest(
      url: _settings.supabaseUrl,
      anonKey: _settings.supabaseAnonKey,
      httpClient: httpClient,
    );
    _rest = made;
    // 换了后台项目 → 水位线没意义了，下一次重新全量拉一遍
    _since = null;
    return made;
  }

  /// 启动：把设备名交给 PosController（改单时会写进去），并开始定时同步。
  void start() {
    if (_started) return;
    _started = true;
    pos.deviceId = deviceName;
    _refreshPending();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    // 用 microtask 推第一趟：避免在「设置刚通知完」的那一帧里同步改界面状态
    scheduleMicrotask(() => unawaited(syncNow()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 防抖那个也得取消：不然销毁之后它还会醒过来调 syncNow() → 对已销毁的对象
    // notifyListeners() 会抛「used after being disposed」
    _debounce?.cancel();
    _rest?.close();
    super.dispose();
  }

  /// 设置改了（设备名 / 开关 / 账号）时调用。
  void onSettingsChanged() {
    pos.deviceId = deviceName;
    if (_settings.syncEnabled) {
      start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _refreshPending();
    notifyListeners();
  }

  /// 防抖用的定时器：本地一变就重排一个「2 秒后同步」（见 [_scheduleSync]）。
  Timer? _debounce;

  /// 本地单子变了（点单/改单/结账）→ 更新「待上传」并顺手推一次（防抖）。
  void onLocalOrdersChanged() {
    _refreshPending();
    _scheduleSync();
  }

  /// 本地菜单改了（菜品管理 / Excel 导入）→ 标脏，等下一次同步推上去。
  void onLocalMenuChanged() {
    _settings.menuDirty = true;
    unawaited(settingsCtl.persist());
    // 设置页那行「菜单待上传」要马上显示出来
    notifyListeners();
    _scheduleSync();
  }

  /// 菜单有没有还没推上去的改动（设置页显示用）。
  bool get menuPending => _settings.menuDirty;

  /// 要同步时**统一走它**：防抖 2 秒再推一次。
  ///
  /// 为什么防抖：改菜单（尤其 Excel 导入 / 一条条改菜）会连着触发很多次，
  /// 每改一个字就同步一趟的话，服务器上菜单版本号会被顶得飞快，
  /// 别的设备也会跟着一遍遍拉菜单。
  void _scheduleSync() {
    if (!_settings.syncEnabled || !isConfigured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  void _refreshPending() {
    final pending = pos.ordersSnapshot().where((o) => o.dirty).length +
        pos.pendingDeletedIds.length;
    _status = SyncStatus(
      busy: _status.busy,
      lastSyncAt: _status.lastSyncAt,
      error: _status.error,
      pendingOrders: pending,
      pushed: _status.pushed,
      pulled: _status.pulled,
    );
  }

  /// 测试连接：登录 + 问一下服务器时间。
  Future<bool> testConnection() async {
    final rest = _client;
    if (rest == null) {
      _fail('还没填后台地址 / anon key / 登录邮箱');
      return false;
    }
    try {
      await _ensureSignedIn(rest);
      await rest.serverTime();
      _status = SyncStatus(
        lastSyncAt: _status.lastSyncAt,
        pendingOrders: _status.pendingOrders,
        pushed: _status.pushed,
        pulled: _status.pulled,
      );
      notifyListeners();
      return true;
    } catch (e, st) {
      _fail(e, st);
      return false;
    }
  }

  /// 同步一次：**拉 → 合并 → 推**（订单）+ 菜单单向同步。
  ///
  /// 里面还处理了一件容易忽略的事：Supabase 的 access token **默认 1 小时就过期**，
  /// 过期后所有请求都会 401。这里遇到 401 会**清掉会话、重登一次再试一遍**
  /// （只重试一次，避免密码错的时候死循环）。
  Future<void> syncNow() async {
    if (_status.busy) return;
    if (!_settings.syncEnabled) return;
    final rest = _client;
    if (rest == null) return;

    _status = SyncStatus(
      busy: true,
      lastSyncAt: _status.lastSyncAt,
      // 推/拉的计数留着：万一这次失败，界面上的数字不会闪成 0
      pendingOrders: _status.pendingOrders,
      pushed: _status.pushed,
      pulled: _status.pulled,
    );
    _refreshPending(); // 顺手把「待上传」算准（保留 busy / lastSyncAt）
    notifyListeners();

    ({int pushed, int pulled}) result;
    _skippedBadRows = 0;
    try {
      result = await _syncAll(rest);
    } on SupabaseError catch (e, st) {
      if (e.statusCode != 401) {
        _fail(e, st);
        return;
      }
      // token 过期（或没有权限）→ 清掉会话重新登录，再试一遍
      rest.clearSession();
      _settings.syncRefreshToken = '';
      await settingsCtl.persist();
      try {
        result = await _syncAll(rest);
      } catch (e2, st2) {
        _fail(e2, st2);
        return;
      }
    } catch (e, st) {
      _fail(e, st);
      return;
    }

    // ---- 记录成功 ----
    final now = DateTime.now();
    _settings.lastSyncAt = now.toIso8601String();
    await settingsCtl.persist();
    _status = SyncStatus(
      lastSyncAt: now,
      pushed: result.pushed,
      pulled: result.pulled,
      // 有坏数据就提醒一句（不当作失败：其它单照样同步过去了）
      error: _skippedBadRows == 0
          ? null
          : '${L10n.t('sync.badRows')} ($_skippedBadRows)',
    );
    _refreshPending(); // 重算「待上传」并保留上面的时间/pushed/pulled
    notifyListeners();
  }

  /// 真正干活的：拉别人的 → 推自己的 → 同步菜单。
  Future<({int pushed, int pulled})> _syncAll(SupabaseRest rest) async {
    await _ensureSignedIn(rest);

    // ---- 1) 拉：别人的改动（**增量**：只拉水位线之后变过的行）----
    final pulled = await _pullOrders(rest, since: _since);
    final remote = <String, RemoteOrder>{
      for (final r in pulled)
        if ((r['id'] ?? '').toString().isNotEmpty)
          (r['id']).toString(): RemoteOrder.fromRow(r),
    };
    final local = pos.ordersSnapshot();
    final incoming = OrderSync.chooseIncoming(
      local,
      remote,
      // 服务器那一行数据不完整（被手改过之类）→ 跳过 + 在控制台里把**整行内容**
      // 打出来（含 payload），这样一眼就知道是哪张单、缺什么
      onBadRow: (bad) {
        _skippedBadRows++;
        debugPrint('后台同步：服务器上的单 ${bad.id} 数据不完整，已跳过。'
            'payload=${bad.payload}');
      },
    );
    if (incoming.isNotEmpty) pos.adoptServerOrders(incoming);

    // 水位线往前挪：只由**拉回来的行**决定（一行都没拉到就不动）——
    // 这样哪怕这趟只拉了一半（保险丝/接口上限），下一趟也从这批行之后接着拉，
    // 既不会卡住，也不会漏掉中间的行。serverTime 只当上限兜底。
    final next = OrderSync.nextWatermark(
      serverTime: rest.lastServerTime,
      rowTimes: pulled.map((r) => RemoteOrder.fromRow(r).updatedAt),
    );
    if (next != null) _since = next.toIso8601String();

    // ---- 1b) 对账：别人**删掉**的进行中单，本地也要跟着删 ----
    // 这一步是「尽力而为」：它失败了也不能影响下面更重要的推送（下一趟还会再对账）。
    try {
      await _reconcileDeletedInProgress(rest);
    } catch (_) {
      // 忽略：多半是网络抖了一下
    }

    // ---- 2) 推：本地脏数据 ----
    final outgoing = OrderSync.chooseOutgoing(pos.ordersSnapshot(), remote);
    var pushed = 0;

    // 2a) 已结账的单优先走 close_order()（服务器做 CAS，只成功一次）
    for (final o in outgoing.where((o) => !o.isInProgress)) {
      final row = await rest.rpc('close_order', {
        'p_id': o.id,
        // 送**整份本地 JSON**（不只结账字段）：结账前刚加的菜/改的桌号不能丢
        'p_patch': OrderSync.closePatch(o, deviceId: deviceName),
        'p_device': deviceName,
      });
      // 只有「回包确实是**我们这张单**、而且能解析」才采纳；
      // 其它情况（服务器上没这张单 / 回包是一行全 NULL / 数据不完整）
      // 一律**整单推上去** —— 结完账的单绝对不能就这么上不了后台。
      final rowId = row == null ? '' : (row['id'] ?? '').toString();
      if (row != null && rowId == o.id) {
        final back = OrderSync.tryOrderFromRemote(RemoteOrder.fromRow(row));
        if (back != null) {
          pos.adoptServerOrders([back]);
          pushed++;
          continue;
        }
        _skippedBadRows++;
        debugPrint('后台同步：结账回包里的单 $rowId 解析失败，改成整单推上去');
      }
      await _upsertOrders(rest, [o]);
      pushed++;
    }

    // 2b) 其余（进行中的单）整单 upsert
    final inProgressDirty = outgoing.where((o) => o.isInProgress).toList();
    if (inProgressDirty.isNotEmpty) {
      await _upsertOrders(rest, inProgressDirty);
      pushed += inProgressDirty.length;
    }

    // 2c) 本地删掉的单 → 服务器也删
    final deleted = pos.pendingDeletedIds.where(_safeId).toList();
    if (deleted.isNotEmpty) {
      await rest.delete('orders', {'id': 'in.(${deleted.join(',')})'});
      pos.confirmDeletedPush(deleted);
    }

    // ---- 3) 菜单（单向：谁版本高听谁的）----
    await _syncMenu(rest);

    return (pushed: pushed, pulled: incoming.length);
  }

  /// 拉订单（**增量 + 翻页**）。
  ///
  /// - [since] 为 null（App 刚启动、换了后台项目、点了「重置同步状态」）→ **全量**拉，
  ///   这样新加入的设备能把整个单池（含历史）拉全；
  /// - 之后每趟只拉 `updated_at > since` 的行 —— 稳定状态下基本是「0 行」，
  ///   不再每次把几个月的历史单全下载一遍（省流量、也省时间）；
  /// - **必须翻页**：Supabase 的接口单次最多给 1000 行、且不翻页就是静默截断
  ///   （历史单一多，新单就永远拉不到了）；
  /// - [maxPullRows] 是保险丝：一趟最多拉这么多行，剩下的**下一趟接着拉**
  ///   （水位线是按「拉到的那批行的时间」推进的，所以既不会卡住也不会漏）。
  Future<List<Map<String, dynamic>>> _pullOrders(
    SupabaseRest rest, {
    String? since,
  }) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final rows = await rest.select(
        'orders',
        select: 'id,status,rev,updated_at,data',
        filters:
            since == null ? const {} : <String, String>{'updated_at': 'gt.$since'},
        order: 'updated_at.asc,id.asc',
        limit: pageSize,
        offset: offset,
      );
      out.addAll(rows);
      if (rows.length < pageSize) break; // 这一页没满 → 拉完了
      offset += rows.length;
      if (out.length >= maxPullRows) break; // 保险丝：剩下的下一趟继续
    }
    return out;
  }

  /// 对账：**别人删掉的进行中单**，本地也删掉。
  ///
  /// 为什么需要这一步：删单只会在这台设备留下「待删除」标记推给服务器，
  /// 别的设备根本不知道 —— 没有这一步，A 上取消了一张单，B 上会一直挂着，
  /// 甚至被再结一次账。
  ///
  /// 做法很便宜（只问本地这几张单的情况，不拉全表）：
  /// - 服务器上**还在**（哪怕已经是「已结账」）→ 不动它，结账那份会走正常合并；
  /// - 服务器上**确实没有** → 是被删了 → 本地也删。
  ///
  /// ⚠️ **只对「进行中」的单做这件事**：已结账的历史留在本机（日结要用），
  /// 万一后台清过老数据，不能让本机的历史跟着消失。
  Future<void> _reconcileDeletedInProgress(SupabaseRest rest) async {
    final candidates = pos
        .ordersSnapshot()
        .where((o) =>
            o.isInProgress &&
            o.rev > 0 && // 推上去过，才有「服务器上有没有」这回事
            !o.dirty && // 本地刚改过还没推 → 先推上去，别删
            _safeId(o.id))
        .map((o) => o.id)
        .toList();
    if (candidates.isEmpty) return;

    final rows = await rest.select(
      'orders',
      select: 'id',
      filters: <String, String>{'id': 'in.(${candidates.join(',')})'},
    );
    final alive = rows.map((r) => (r['id'] ?? '').toString()).toSet();
    final gone = candidates.where((id) => !alive.contains(id)).toList();
    if (gone.isNotEmpty) pos.dropOrdersRemovedOnServer(gone);
  }

  /// 单号能不能安全地拼进 PostgREST 的 `in.(...)`（只允许字母/数字/`-`/`_`）。
  /// 我们的单号本来就是时间戳格式，这里只是防御奇怪的老数据把查询串搞坏。
  static bool _safeId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  Future<void> _upsertOrders(SupabaseRest rest, List<Order> orders) async {
    if (orders.isEmpty) return;
    // 记下「我们这一次发出去的是哪一版」，回来的时候用来判断本机有没有又改过
    final sentAt = {for (final o in orders) o.id: o.updatedAt};
    final rows = orders
        .map((o) => OrderSync.toRow(o, deviceId: deviceName))
        .toList();
    final back = await rest.upsert('orders', rows);
    if (back.isEmpty) return;
    // 把服务器那份（rev/updated_at）存回本地，dirty 清掉
    final adopted = <Order>[];
    for (final r in back) {
      final remote = RemoteOrder.fromRow(r);
      final cur = pos.findOrder(remote.id);
      // ⚠️ 请求「在路上」的时候收银员又改了这张单（现在还是脏的）→ **不要**用服务器
      // 那份盖掉，否则刚加的那道菜会悄没声地消失。下一次同步会把新版本再推一遍。
      final changedWhilePushing =
          cur != null && cur.dirty && cur.updatedAt != sentAt[remote.id];
      if (changedWhilePushing) continue;
      // 服务器回给我们的那份理论上就是我们刚发上去的；万一它不完整（被人手改过），
      // 就跳过这一张，别让类型错误把整趟同步搞失败。
      final parsed = OrderSync.tryOrderFromRemote(remote);
      if (parsed == null) {
        _skippedBadRows++;
        debugPrint('后台同步：服务器回包里的单 ${remote.id} 解析失败，已跳过');
        continue;
      }
      adopted.add(parsed);
    }
    if (adopted.isEmpty) return;
    pos.adoptServerOrders(adopted);
  }

  /// 菜单同步：服务器版本更高就拉下来（覆盖本地），本地改过就推上去。
  Future<void> _syncMenu(SupabaseRest rest) async {
    final rows = await rest.select('menu', filters: {'id': 'eq.current'});
    if (rows.isEmpty) {
      // 服务器上还没有菜单 → 把本地的推上去（第一次接入时用）
      await _pushMenu(rest);
      return;
    }
    final serverVersion = (rows.first['version'] as num?)?.toInt() ?? 0;
    final localVersion = _settings.menuVersion;

    if (_settings.menuDirty) {
      await _pushMenu(rest);
      return;
    }
    if (serverVersion > localVersion) {
      final raw = rows.first['data'];
      if (raw is! Map) return;
      final data = raw.cast<String, dynamic>();
      MenuData? parsed;
      try {
        parsed = _menuDataFromJson(data);
      } catch (e, st) {
        // 服务器上的菜单数据不完整（被人手改过之类）→ **不能**拿它覆盖本地菜单，
        // 也不能让整个同步一直失败（那样连单子都推不上去了）。提醒一句就跳过。
        _skippedBadRows++;
        debugPrint('后台同步：服务器上的菜单数据解析失败，已跳过：$e');
        debugPrint('$st');
        return;
      }
      if (parsed == null) return;
      pos.replaceMenuFromServer(parsed);
      _settings.menuVersion = serverVersion;
      _settings.menuDirty = false;
      await settingsCtl.persist();
    }
  }

  Future<void> _pushMenu(SupabaseRest rest) async {
    final data = pos.menuSnapshot();
    final back = await rest.upsert('menu', [
      {
        'id': 'current',
        'data': {
          'categories': data.categories.map((c) => c.toJson()).toList(),
          'items': data.items.map((m) => m.toJson()).toList(),
        },
      }
    ]);
    final version =
        back.isEmpty ? null : (back.first['version'] as num?)?.toInt();
    _settings.menuVersion = version ?? _settings.menuVersion + 1;
    _settings.menuDirty = false;
    await settingsCtl.persist();
  }

  /// **重置同步状态**：忘了登录态、把所有本地单和菜单重新标成「要推」，
  /// 然后马上同步一次。
  ///
  /// 什么时候用：换了后台项目 / 账号密码不对一直失败 / 数据看着不同步想重来一遍。
  /// **只动同步标记，不删单子、不改金额。**
  Future<void> resetSyncState() async {
    _settings.syncRefreshToken = '';
    _settings.menuVersion = 0;
    _settings.menuDirty = true;
    _settings.lastSyncAt = '';
    await settingsCtl.persist();
    pos.markAllOrdersDirty();
    _rest?.close();
    _rest = null;
    _since = null; // 水位线清掉 → 下一次重新全量拉一遍
    notifyListeners();
    await syncNow();
  }

  static MenuData _menuDataFromJson(Map<String, dynamic> data) => MenuData(
        categories: ((data['categories'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Category.fromJson(e.cast<String, dynamic>()))
            .toList(),
        items: ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MenuItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  Future<void> _ensureSignedIn(SupabaseRest rest) async {
    if (rest.hasSession) return;
    final refresh = _settings.syncRefreshToken;
    if (refresh.isNotEmpty) {
      try {
        await rest.refreshSession(refresh);
      } catch (_) {
        // refresh token 过期了 → 用账号密码重新登录
        await rest.signIn(_settings.syncEmail, _settings.syncPassword);
      }
    } else {
      await rest.signIn(_settings.syncEmail, _settings.syncPassword);
    }
    final token = rest.refreshToken;
    if (token != null && token.isNotEmpty && token != _settings.syncRefreshToken) {
      _settings.syncRefreshToken = token;
      await settingsCtl.persist();
    }
  }

  void _fail(Object e, [StackTrace? st]) {
    final msg = e is SupabaseError ? e.message : '$e';
    // 控制台里留一份**带堆栈**的：像「type 'NULL' is not a subtype of type 'String'
    // in type cast」这种错误，光看消息根本不知道是哪一行 —— 有堆栈就能直接定位
    // （跑 `flutter run` 的时候会在终端里打出来）。
    debugPrint('后台同步出错：$msg');
    if (st != null) debugPrint('$st');
    _status = SyncStatus(
      lastSyncAt: _status.lastSyncAt,
      error: msg,
      pendingOrders: _status.pendingOrders,
      pushed: _status.pushed,
      pulled: _status.pulled,
    );
    notifyListeners();
  }
}
