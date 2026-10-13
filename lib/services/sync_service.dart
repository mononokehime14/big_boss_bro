import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:http/http.dart' as http;

import '../data/menu_store.dart';
import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../state/attendance_controller.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import 'attendance_sync.dart';
import 'order_sync.dart';
import 'store_settings_sync.dart';
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

/// **云端那份菜单**的摘要（设置页显示用）。
///
/// 为什么要给用户看这个：菜单和订单/店级配置是**各走各的**三条线 ——
/// 菜单按「版本号」同步，而店级配置里**不含菜品**。真实踩过：
/// 在收银机上重新导入 Excel（菜里带了新的「基础数量」），再点「上传本机配置」，
/// 以为平板就能拿到 —— 结果平板上的菜单还是旧的那份（没有 `minQuantity`），
/// 「2 份起」自然不生效。有这行摘要，一眼就能比出「本机 3 道几份起 / 云端 0 道」。
class CloudMenuInfo {
  /// 服务器上的菜单版本号（每次上传 +1，设备比它决定要不要拉）。
  final int version;

  /// 云端菜单里有几道菜。
  final int itemCount;

  /// 其中**几份起**（`minQuantity > 1`）的有几道。
  final int minQtyCount;

  const CloudMenuInfo({
    required this.version,
    required this.itemCount,
    required this.minQtyCount,
  });

  /// 从 `menu` 表那一行算出来（**只数 JSON 里的条数**，不建模型 —— 每趟同步都会调）。
  factory CloudMenuInfo.fromRow(Map<String, dynamic> row) {
    final data = row['data'];
    final items = (data is Map ? data['items'] : null);
    final list = items is List ? items : const [];
    var minQty = 0;
    for (final it in list) {
      if (it is Map && ((it['minQuantity'] as num?)?.toInt() ?? 1) > 1) minQty++;
    }
    return CloudMenuInfo(
      version: (row['version'] as num?)?.toInt() ?? 0,
      itemCount: list.length,
      minQtyCount: minQty,
    );
  }
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

  /// 员工考勤（员工名单 + 打卡记录）。
  final AttendanceController attendance;

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

  /// 打卡记录的增量水位线（按服务器写的 `created_at` 走，跟订单同一个思路）。
  String? _punchSince;

  /// 一次拉多少行（Supabase 的接口单次最多给 1000 行，所以必须翻页）。
  /// 测试里会调小来验证翻页逻辑。
  final int pageSize;

  /// 一趟同步最多拉多少行（保险丝：历史单特别多时别把这一趟拖太久/占太多内存，
  /// 剩下的下一趟接着拉 —— 水位线是按数据推进的，所以不会卡住也不会漏）。
  static const int maxPullRows = 10000;

  /// 这一趟跳过了几张「服务器上数据不完整」的单（正常 0）。
  /// 不为 0 时会在状态里提醒一句（不是失败：其它单照常同步）。
  int _skippedBadRows = 0;

  /// 这一趟考勤同步的提醒（比如「后台还没建考勤表」）；正常为 null。
  ///
  /// 为什么单独一个字段而不是直接抛错：考勤表要用户自己去 Supabase 跑一遍 SQL
  /// 才会存在（404）。没建好**不能**把订单/菜单的同步一起搞挂 ——
  /// 收银照常，只是状态栏提醒一句。
  String? _attendanceWarning;

  /// 这一趟「店级配置」同步的结果说明（值是一个 `L10n.t()` 的 key）；正常为 null。
  ///
  /// 为什么单独一个字段：**表还没建（404）不能算同步失败** ——
  /// 订单/菜单/考勤都照常，只是提醒一句（跟 [_attendanceWarning] 一个思路，
  /// 区别是这个不写进 `status.error`，因为它不是错误）。
  String? _settingsNote;

  /// **手动**菜单同步（上传 / 下载）的结果说明（`L10n.t()` 的 key）；正常为 null。
  ///
  /// 跟 [_settingsNote] 一个套路：菜单表没建 / 云端还没有菜单都不算「同步失败」。
  String? _menuNote;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  /// 正在同步（界面按钮用它变灰）。
  bool get busy => _status.busy;

  /// 同步间隔（前台每 [interval] 拉一次别人的改动）。
  static const Duration interval = Duration(seconds: 25);

  SyncService({
    required this.pos,
    required this.settingsCtl,
    required this.attendance,
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

  /// 设置改了（设备名 / 开关 / 账号 / 店级配置）时调用。
  void onSettingsChanged() {
    pos.deviceId = deviceName;
    if (_settings.syncEnabled) {
      start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _refreshPending();
    // 店级配置（店名 / 税率 / 货币 / 桌号 / 备注 / 日结支出…）改了就顺手推一趟。
    // 判断靠「和上次同步的内容比」——所以改打印机地址这种本机专属设置
    // **不会**白白触发一次上传（那些字段不参与同步，见 StoreSettingsSync.toData）。
    if (settingsPending) _scheduleSync();

    // 刚把"缺的那一项"补齐（地址 / key / 邮箱 / 密码，通常是新设备上刚输的密码）
    // → 不用等下一个 25 秒，2 秒后就同步一次。
    final incomplete = syncBlockedReason != null;
    if (_configWasIncomplete && !incomplete) _scheduleSync();
    _configWasIncomplete = incomplete;

    notifyListeners();
  }

  /// 上一次看到的"同步配置是不是还不齐"（用来发现用户刚把密码填上）。
  bool _configWasIncomplete = false;

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

  /// **手动**菜单同步（上传 / 下载）的结果说明（`L10n.t()` 的 key）；正常为 null。
  String? get menuNote => _menuNote;

  /// 本机菜单的摘要（设置页显示用）：**道菜数 + 有几道是「几份起」**。
  ///
  /// 「几份起」那道数很重要：菜单同步出问题时，一眼就能看出
  /// 「本机 3 道 / 云端 0 道」——说明弹性数量（`minQuantity`）根本没传到这台设备上。
  ({int items, int minQty}) get localMenuSummary => (
        items: pos.menu.length,
        minQty: pos.menu.where((m) => m.hasMinQuantity).length,
      );

  /// **云端**那份菜单的摘要（版本号 / 道菜数 / 有几道「几份起」）。
  ///
  /// 每次同步读到 `menu` 表那一行就顺手更新（只数 JSON 里的条数，不建模型，很便宜）。
  /// 从没读到过（没同步过 / 表没建）就是 null。
  CloudMenuInfo? _cloudMenu;
  CloudMenuInfo? get cloudMenu => _cloudMenu;

  /// **店级配置**有没有本机改动还没推上去（设置页显示用）。
  ///
  /// 判断方式：把当前店级配置序列化成 JSON，和「上次同步时服务器上的内容」比。
  /// 从没同步过（[Settings.storeSettingsSyncedJson] 为空）→ **不算本机改动** ——
  /// 新设备第一次接入时以服务器那份为准（这正是"换台平板就自动拿到旧配置"的关键）。
  bool get settingsPending =>
      StoreSettingsSync.hasLocalChanges(_settings, _settings.storeSettingsSyncedJson);

  /// 这一趟对店级配置做了什么（值是 `L10n.t()` 的 key；null = 这一趟没动它）。
  String? get settingsNote => _settingsNote;

  /// 本地**员工名单**改了（加/删/改名/改 PIN）→ 标脏 + 防抖推。
  void onLocalStaffChanged() {
    _settings.staffDirty = true;
    unawaited(settingsCtl.persist());
    notifyListeners();
    _scheduleSync();
  }

  /// **有新打卡**（上班/下班）→ 防抖推一趟：老板在后台很快就能看到。
  void onLocalPunchesChanged() {
    _refreshPending();
    notifyListeners();
    _scheduleSync();
  }

  /// 考勤里还有几条没推上去（设置页状态行显示用）。
  int get attendancePending => attendance.unpushedPunches.length +
      (_settings.staffDirty ? 1 : 0);

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
        pos.pendingDeletedIds.length +
        // 还没推上去的打卡也算「待上传」（设置页那行显示的是总数）
        attendance.unpushedPunches.length;
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
    // 还没填登录密码 → **静默跳过**。
    // 为什么：开关现在是默认打开的（URL/key/邮箱都有预填值），
    // 不挡住的话每 25 秒就会试一次登录、报一次「Invalid login credentials」，
    // 既吓人又可能撞上 Supabase 的登录限流。设置页那行橙字会提示"还没填登录密码"。
    if (_settings.syncPassword.isEmpty) return;
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
    _attendanceWarning = null;
    _settingsNote = null;
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
      // 有坏数据 / 考勤表没建好 → 提醒一句（不算失败：别的照常同步）
      error: _attendanceWarning ??
          (_skippedBadRows == 0
              ? null
              : '${L10n.t('sync.badRows')} ($_skippedBadRows)'),
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

    // ---- 4) 员工考勤（员工名单 + 打卡记录）----
    // 这一步是「尽力而为」：后台要是还没建那两张表（404），记一句提醒就行，
    // **不能**把订单/菜单的同步一起搞挂（收银优先）。
    try {
      await _syncAttendance(rest);
    } on SupabaseError catch (e) {
      _attendanceWarning = e.statusCode == 404
          ? L10n.t('sync.attendanceTableMissing')
          : '${L10n.t('sync.error')}: ${e.message}';
      debugPrint('考勤同步跳过：${e.message}');
    }

    // ---- 5) 店级配置（店名 / 地址 / 税 / 货币 / 桌号 / 备注 / 日结支出）----
    // 新设备第一次接入就是靠这一步把"这家店怎么配置"拿回来的。
    // 同样「尽力而为」：表没建好（404）只记一句提醒，不影响订单/菜单（收银优先）。
    try {
      await _syncSettings(rest);
    } on SupabaseError catch (e) {
      if (e.statusCode != 404) rethrow;
      _settingsNote = 'sync.settingsTableMissing';
      debugPrint('店级配置同步跳过：${e.message}');
    }

    return (pushed: pushed, pulled: incoming.length);
  }

  /// **考勤同步**：两条线，规则都很简单。
  ///
  /// 1. **员工名单**（`attendance_staff`，只有一行）：跟菜单一样按**版本号**走 ——
  ///    本地改过就先推本地（后改的赢），否则服务器版本更高就拉下来整体替换；
  /// 2. **打卡记录**（`attendance_punches`，一次打卡一行）：**只增不改**，
  ///    所以先拉（增量）后推，按 id 并集 —— 两台设备各打各的卡不会互相覆盖。
  ///
  /// 两边都失败也不影响收银/点单：任何异常都会冒到 `syncNow()` 那里记成错误。
  Future<void> _syncAttendance(SupabaseRest rest) async {
    // ---- 4a) 员工名单 ----
    final staffRows =
        await rest.select('attendance_staff', filters: {'id': 'eq.current'});
    if (staffRows.isEmpty) {
      // 服务器上还没有这份名单 → 把本地的推上去（第一次接入时用）
      await _pushStaff(rest);
    } else {
      final serverVersion = (staffRows.first['version'] as num?)?.toInt() ?? 0;
      if (_settings.staffDirty) {
        await _pushStaff(rest);
      } else if (AttendanceSync.shouldPullStaff(
        serverVersion: serverVersion,
        localVersion: _settings.staffVersion,
        localDirty: _settings.staffDirty,
      )) {
        final remote = RemoteStaff.fromRow(staffRows.first);
        // 服务器上是空名单（比如别的设备刚清空）→ 也照拉（跟着清空）
        await attendance.replaceStaffFromServer(remote.staff);
        _settings.staffVersion = serverVersion;
        _settings.staffDirty = false;
        await settingsCtl.persist();
      }
    }

    // ---- 4b) 打卡记录：先拉（增量），再推没上传的 ----
    final pulled = await _pullRows(
      rest,
      table: 'attendance_punches',
      select: 'id,employee_id,kind,at,created_at,device_id',
      timeColumn: 'created_at',
      since: _punchSince,
    );
    if (pulled.isNotEmpty) {
      await attendance.adoptServerPunches(
        pulled.map(AttendanceSync.punchFromRow).toList(),
      );
      // 水位线：按**服务器收到的时间**推进（跟订单共用那个纯函数）
      final next = OrderSync.nextWatermark(
        serverTime: rest.lastServerTime,
        rowTimes: pulled.map(AttendanceSync.punchCreatedAt),
      );
      if (next != null) _punchSince = next.toIso8601String();
    }

    final unpushed = attendance.unpushedPunches;
    if (unpushed.isNotEmpty) {
      await rest.upsert(
        'attendance_punches',
        unpushed
            .map((p) => AttendanceSync.punchToRow(p, deviceId: deviceName))
            .toList(),
      );
      await attendance.markPunchesPushed(unpushed.map((p) => p.id).toList());
    }
  }

  /// 把本地员工名单推上去（`attendance_staff` 只有一行，版本号由触发器维护）。
  Future<void> _pushStaff(SupabaseRest rest) async {
    final back = await rest.upsert('attendance_staff', [
      AttendanceSync.staffToRow(attendance.staffSnapshot(), deviceId: deviceName),
    ]);
    final version =
        back.isEmpty ? null : (back.first['version'] as num?)?.toInt();
    _settings.staffVersion = version ?? _settings.staffVersion + 1;
    _settings.staffDirty = false;
    await settingsCtl.persist();
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
  }) =>
      _pullRows(
        rest,
        table: 'orders',
        select: 'id,status,rev,updated_at,data',
        timeColumn: 'updated_at',
        since: since,
      );

  /// 通用「增量 + 翻页」拉取：订单（`updated_at`）和打卡记录（`created_at`）都用它。
  ///
  /// [timeColumn] 既是「有没有变过」的判断依据，也是排序键 ——
  /// 两者必须是同一列，否则翻页会漏行。
  Future<List<Map<String, dynamic>>> _pullRows(
    SupabaseRest rest, {
    required String table,
    required String select,
    required String timeColumn,
    String? since,
  }) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final rows = await rest.select(
        table,
        select: select,
        filters: since == null
            ? const {}
            : <String, String>{timeColumn: 'gt.$since'},
        order: '$timeColumn.asc,id.asc',
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
      final back = await _pushMenu(rest);
      _cloudMenu = back == null ? null : CloudMenuInfo.fromRow(back);
      return;
    }
    // 顺手记下云端那份的摘要：设置页要显示「云端：v5 · 128 道菜 · 3 道几份起」，
    // 好跟本机那份对一眼（菜单同步出问题时全靠这一行定位）
    _cloudMenu = CloudMenuInfo.fromRow(rows.first);
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

  /// 把本机菜单推到 `menu` 表（只有一行 `id = 'current'`）。
  ///
  /// 返回服务器回给我们的那一行（拿它的 `version`）；没回包就是 null。
  Future<Map<String, dynamic>?> _pushMenu(SupabaseRest rest) async {
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
    final row = back.isEmpty ? null : back.first;
    final version = (row?['version'] as num?)?.toInt();
    _settings.menuVersion = version ?? _settings.menuVersion + 1;
    _settings.menuDirty = false;
    await settingsCtl.persist();
    return row;
  }

  // ---------------- 菜单（手动上传 / 下载）----------------

  /// **手动**：把本机菜单上传到云端（覆盖服务器那份）。**不看版本号**。
  ///
  /// 什么时候用：本机这份才是对的（例如刚重新导入过 Excel，菜里带了「基础数量」），
  /// 但云端被别的设备的旧菜单占着 —— 自动同步那套规矩（谁版本高听谁的）掰不过来。
  Future<bool> pushMenu() async {
    final rest = _client;
    if (rest == null) {
      _fail('还没填后台地址 / anon key / 登录邮箱');
      return false;
    }
    try {
      await _ensureSignedIn(rest);
      final row = await _pushMenu(rest);
      // 刚推上去的那份内容 = 本机这份，所以云端摘要直接按本机算（只从回包里取版本号）——
      // 不依赖服务器有没有把 `data` 回给我们
      final s = localMenuSummary;
      _cloudMenu = CloudMenuInfo(
        version: (row?['version'] as num?)?.toInt() ?? _settings.menuVersion,
        itemCount: s.items,
        minQtyCount: s.minQty,
      );
      _menuNote = 'sync.menuPushed';
      notifyListeners();
      return true;
    } on SupabaseError catch (e, st) {
      if (e.statusCode != 404) {
        _fail(e, st);
        return false;
      }
      _menuNote = 'sync.menuTableMissing';
      notifyListeners();
      return false;
    } catch (e, st) {
      _fail(e, st);
      return false;
    }
  }

  /// **手动**：从云端下载菜单（覆盖本机那份）。**不看版本号**。
  ///
  /// 什么时候用：这台设备的菜单是旧的（换设备 / 新装的平板），
  /// 自动同步又因为「本机也标了要上传」这类状态没拉下来 —— 一刀切地以云端为准。
  Future<bool> pullMenu() async {
    final rest = _client;
    if (rest == null) {
      _fail('还没填后台地址 / anon key / 登录邮箱');
      return false;
    }
    try {
      await _ensureSignedIn(rest);
      final rows = await rest.select('menu', filters: {'id': 'eq.current'});
      if (rows.isEmpty) {
        // 云端还没有：提示"先在一台设备上点上传本机菜单"
        _cloudMenu = null;
        _menuNote = 'sync.menuEmpty';
        notifyListeners();
        return false;
      }
      final info = CloudMenuInfo.fromRow(rows.first);
      final raw = rows.first['data'];
      if (raw is! Map) {
        _menuNote = 'sync.menuBadData';
        notifyListeners();
        return false;
      }
      MenuData parsed;
      try {
        parsed = _menuDataFromJson(raw.cast<String, dynamic>());
      } catch (e) {
        debugPrint('手动下载菜单：云端数据解析失败：$e');
        _menuNote = 'sync.menuBadData';
        notifyListeners();
        return false;
      }
      // 云端那份是空的（被人手改过之类）→ **不能**拿它把本机菜单清空
      if (parsed.items.isEmpty) {
        _menuNote = 'sync.menuBadData';
        notifyListeners();
        return false;
      }
      pos.replaceMenuFromServer(parsed);
      _settings.menuVersion = info.version;
      _settings.menuDirty = false;
      await settingsCtl.persist();
      _cloudMenu = info;
      _menuNote = 'sync.menuPulled';
      notifyListeners();
      return true;
    } on SupabaseError catch (e, st) {
      if (e.statusCode != 404) {
        _fail(e, st);
        return false;
      }
      _menuNote = 'sync.menuTableMissing';
      notifyListeners();
      return false;
    } catch (e, st) {
      _fail(e, st);
      return false;
    }
  }

  // ---------------- 店级配置（store_settings）----------------

  /// **店级配置同步**：表 `store_settings` 永远只有一行（`id = 'current'`）。
  ///
  /// 规则（关键在"本机改没改"怎么判断）：
  /// 1. 服务器上**还没有**这一行 → 只有本机**真的配置过**（不是出厂默认值）才推上去当初始值。
  ///    这条保护很重要：新装的平板里全是默认值，不该抢先把自己的默认配置写成"全店配置"
  ///    （万一平板先跑、收银机后跑，也不会把收银机真正的店名/备注盖掉）；
  /// 2. 本机改过（当前内容和「上次同步的内容」不一样）→ 推本机（后改的赢，跟菜单一个规矩）；
  /// 3. 其它情况（服务器版本更高，**或本机从来没同步过**）→ 拉下来覆盖本机 ——
  ///    新设备第一次接入就走这条：店名 / 地址 / 税率 / 货币 / 桌号 / 备注 / 日结支出 一次拿到。
  Future<void> _syncSettings(SupabaseRest rest) async {
    final rows = await rest.select(
      'store_settings',
      filters: {'id': 'eq.${StoreSettingsSync.rowId}'},
    );

    if (rows.isEmpty) {
      // 云端还没有这份配置：出厂默认值就没什么好推的（也顺便避免了上面第 1 条那个坑）
      if (StoreSettingsSync.isPristine(_settings)) return;
      await _pushSettings(rest, StoreSettingsSync.encode(_settings));
      _settingsNote = 'sync.settingsPushed';
      return;
    }

    final data = StoreSettingsSync.dataFromRow(rows.first);
    if (data == null) {
      // 服务器上那一行被人手改坏了 → 跳过，**不能**拿它覆盖本机配置
      _skippedBadRows++;
      debugPrint('后台同步：服务器上的店级配置数据不完整，已跳过');
      return;
    }
    final serverVersion = (rows.first['version'] as num?)?.toInt() ?? 0;

    if (StoreSettingsSync.hasLocalChanges(
        _settings, _settings.storeSettingsSyncedJson)) {
      await _pushSettings(rest, StoreSettingsSync.encode(_settings));
      _settingsNote = 'sync.settingsPushed';
      return;
    }

    if (serverVersion > _settings.storeSettingsVersion ||
        _settings.storeSettingsSyncedJson.isEmpty) {
      await _applySettings(data, serverVersion);
      _settingsNote = 'sync.settingsPulled';
    }
  }

  /// 把本机店级配置推上去，并把「版本号 / 服务器上现在是什么内容」记回本地。
  Future<void> _pushSettings(SupabaseRest rest, String localJson) async {
    final back = await rest.upsert('store_settings', [
      StoreSettingsSync.toRow(_settings, deviceId: deviceName),
    ]);
    final version =
        back.isEmpty ? null : (back.first['version'] as num?)?.toInt();
    _settings.storeSettingsVersion =
        version ?? _settings.storeSettingsVersion + 1;
    // 基线记**发出去的那份字符串**（不是重新 encode 一遍），这样和服务器上的内容严格对应。
    _settings.storeSettingsSyncedJson = localJson;
    await settingsCtl.persist();
  }

  /// 用服务器那份覆盖本机的**店级**配置。
  ///
  /// 打印机地址 / 纸宽 / 小票编码 / 后台账号这些**本机专属**的字段一个字都不动。
  Future<void> _applySettings(
      Map<String, dynamic> data, int serverVersion) async {
    await settingsCtl.update((s) {
      StoreSettingsSync.applyTo(s, data);
      s.storeSettingsVersion = serverVersion;
      // 基线取「把服务器那份应用之后的本机内容」：服务器上可能有我们不认识的键、
      // 也可能少几个键（被本机默认值补上）——这样下次同步才不会误判成"本机改过"
      // 而反复推上去（两台设备互相顶版本号，永远同步不完）。
      s.storeSettingsSyncedJson = StoreSettingsSync.encode(s);
    });
  }

  /// **手动**：把本机的店级配置上传到云端（覆盖服务器那份）。
  ///
  /// 什么时候用：云端被"先跑的那台设备"的配置占了、但本机这份才是全店该用的配置。
  Future<bool> pushStoreSettings() async {
    final rest = _client;
    if (rest == null) {
      _fail('还没填后台地址 / anon key / 登录邮箱');
      return false;
    }
    try {
      await _ensureSignedIn(rest);
      await _pushSettings(rest, StoreSettingsSync.encode(_settings));
      _settingsNote = 'sync.settingsPushed';
      notifyListeners();
      return true;
    } on SupabaseError catch (e, st) {
      if (e.statusCode != 404) {
        _fail(e, st);
        return false;
      }
      _settingsNote = 'sync.settingsTableMissing';
      notifyListeners();
      return false;
    } catch (e, st) {
      _fail(e, st);
      return false;
    }
  }

  /// **手动**：从云端恢复店级配置（覆盖本机）。
  ///
  /// 什么时候用：新设备已经同步过一次但配置看着不对，或者想强制"以云端为准"。
  Future<bool> pullStoreSettings() async {
    final rest = _client;
    if (rest == null) {
      _fail('还没填后台地址 / anon key / 登录邮箱');
      return false;
    }
    try {
      await _ensureSignedIn(rest);
      final rows = await rest.select(
        'store_settings',
        filters: {'id': 'eq.${StoreSettingsSync.rowId}'},
      );
      if (rows.isEmpty) {
        // 云端还没有：提示"先在一台设备上点上传本机配置"
        _settingsNote = 'sync.settingsEmpty';
        notifyListeners();
        return false;
      }
      final data = StoreSettingsSync.dataFromRow(rows.first);
      if (data == null) {
        _settingsNote = 'sync.settingsBadData';
        notifyListeners();
        return false;
      }
      await _applySettings(data, (rows.first['version'] as num?)?.toInt() ?? 0);
      _settingsNote = 'sync.settingsPulled';
      notifyListeners();
      return true;
    } on SupabaseError catch (e, st) {
      if (e.statusCode != 404) {
        _fail(e, st);
        return false;
      }
      _settingsNote = 'sync.settingsTableMissing';
      notifyListeners();
      return false;
    } catch (e, st) {
      _fail(e, st);
      return false;
    }
  }

  /// **重置同步状态**：忘了登录态、把所有本地单和菜单重新标成「要推」，
  /// 然后马上同步一次。
  ///
  /// 什么时候用：换了后台项目 / 账号密码不对一直失败 / 数据看着不同步想重来一遍。
  /// **只动同步标记，不删单子、不改金额。**
  ///
  /// 注意：**店级配置不在这里重置**（它没有"脏标记"，而是每次同步拿内容和服务器那份比）。
  /// 想强制覆盖某一头，用设置页那两颗按钮：「上传本机配置」/「从云端恢复配置」。
  Future<void> resetSyncState() async {
    _settings.syncRefreshToken = '';
    _settings.menuVersion = 0;
    _settings.menuDirty = true;
    _settings.staffVersion = 0;
    _settings.staffDirty = true;
    _settings.lastSyncAt = '';
    await settingsCtl.persist();
    pos.markAllOrdersDirty();
    // 考勤也一样：所有打卡重新标成「要推」（推上去是 upsert，不会重复记账）
    await attendance.markAllPunchesUnpushed();
    _rest?.close();
    _rest = null;
    _since = null; // 水位线清掉 → 下一次重新全量拉一遍
    _punchSince = null;
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
