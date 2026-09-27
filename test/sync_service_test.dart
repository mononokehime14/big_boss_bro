import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/sample_menu.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/sync_service.dart';
import 'package:big_boss_bro/state/pos_controller.dart';
import 'package:big_boss_bro/state/settings_controller.dart';

/// 一台「假服务器」+ 一台配置好的 App（[setup] 的返回值）。
typedef TestRig = ({
  SyncService sync,
  PosController pos,
  SettingsController settings,
  List<http.Request> seen,
});

/// 同步引擎（SyncService）的端到端测试：**用一个假服务器**（MockClient）跑
/// 「拉 → 合并 → 推」，不联网。
///
/// 盯的是几件最要命的事：
/// - 脏单会被推上去，并且把服务器的 rev/updated_at 存回本地、dirty 清掉；
/// - 别的设备开的单会被拉下来；
/// - 已结账的单走 `close_order` RPC（CAS，只成功一次）；
/// - **网络出错绝不能把异常抛出去**（收银不能被同步搞崩），本地单还是脏的、下次再推；
/// - 本地删掉的单会真的从服务器删掉。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 一台「假服务器」+ 一台配置好的 App。
  Future<TestRig> setup(
    Future<http.Response> Function(http.Request req) handler, {
    int pageSize = 1000,
  }) async {
    final pos = PosController();
    pos.deviceId = '收银台A';
    final settingsCtl = SettingsController();
    await settingsCtl.load();
    await settingsCtl.updateSync((s) {
      s.syncEnabled = true;
      s.supabaseUrl = 'https://demo.supabase.co';
      s.supabaseAnonKey = 'anon';
      s.syncEmail = 'device1@bossbro.local';
      s.syncPassword = 'pw';
      s.deviceName = '收银台A';
    });

    final seen = <http.Request>[];
    final sync = SyncService(
      pos: pos,
      settingsCtl: settingsCtl,
      httpClient: MockClient((req) async {
        seen.add(req);
        return handler(req);
      }),
      pageSize: pageSize,
    );
    return (sync: sync, pos: pos, settings: settingsCtl, seen: seen);
  }

  http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  /// 默认的假服务器：登录 OK、订单表空、菜单表空。
  Future<http.Response> defaultHandler(http.Request req) async {
    final path = req.url.path;
    if (path == '/auth/v1/token') {
      return json({'access_token': 'AT', 'refresh_token': 'RT'});
    }
    if (path == '/rest/v1/orders' && req.method == 'GET') return json([]);
    if (path == '/rest/v1/orders' && req.method == 'POST') {
      final rows = (jsonDecode(req.body) as List).cast<Map>();
      return json(rows
          .map((r) => {
                ...r.cast<String, dynamic>(),
                'rev': 1,
                'updated_at': '2026-09-20T12:00:00Z',
              })
          .toList());
    }
    if (path == '/rest/v1/menu' && req.method == 'GET') return json([]);
    if (path == '/rest/v1/menu' && req.method == 'POST') {
      return json([
        {'id': 'current', 'version': 1}
      ]);
    }
    return json({'message': 'unexpected ${req.method} $path'}, 404);
  }

  Order localOrder({
    String id = 'n1',
    bool closed = false,
    bool dirty = true,
    int rev = 0,
    double total = 28,
  }) =>
      Order(
        id: id,
        createdAt: DateTime(2026, 9, 20, 11),
        lines: const [OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28)],
        total: total,
        status: closed ? OrderStatus.completed : OrderStatus.inProgress,
        closedAt: closed ? DateTime(2026, 9, 20, 12) : null,
        paymentMethod: closed ? PaymentMethod.cash : null,
        deviceId: '收银台A',
        rev: rev,
        dirty: dirty,
      );

  test('本地的脏单会被推上去，服务器的 rev 会存回本地、dirty 清掉', () async {
    final s = await setup(defaultHandler);
    s.pos.adoptServerOrders([localOrder()]);
    expect(s.pos.findOrder('n1')!.dirty, isTrue);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(s.sync.status.lastSyncAt, isNotNull);
    expect(s.sync.status.pushed, 1);

    final pushed = s.seen.firstWhere(
        (r) => r.url.path == '/rest/v1/orders' && r.method == 'POST');
    final body = (jsonDecode(pushed.body) as List).first as Map;
    expect(body['id'], 'n1');
    expect(body['status'], 'in_progress');
    expect(body['device_id'], '收银台A');
    expect((body['data'] as Map)['dirty'], isFalse,
        reason: '送上去的那份不带本地脏标记');

    final after = s.pos.findOrder('n1')!;
    expect(after.rev, 1, reason: '服务器返回的 rev 要存回本地');
    expect(after.dirty, isFalse, reason: '推成功了就不再是脏的');
    expect(s.sync.status.pendingOrders, 0);
  });

  test('别的设备开的单会被拉下来（dirty=false）', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        return json([
          {
            'id': 'other-1',
            'status': 'in_progress',
            'rev': 2,
            'updated_at': '2026-09-20T12:30:00Z',
            'data': localOrder(id: 'other-1').toJson(),
          }
        ]);
      }
      return defaultHandler(req);
    });

    await s.sync.syncNow();

    final pulled = s.pos.findOrder('other-1');
    expect(pulled, isNotNull, reason: '别的设备开的单要出现在本机');
    expect(pulled!.rev, 2);
    expect(pulled.dirty, isFalse, reason: '拉下来的不用再推回去');
    expect(s.sync.status.pulled, 1);
    // 本地没有脏单 → 不该有 upsert
    expect(
      s.seen.any((r) => r.url.path == '/rest/v1/orders' && r.method == 'POST'),
      isFalse,
    );
  });

  test('已结账的单走 close_order RPC（CAS：只成功一次），返回的现状被采纳', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/rpc/close_order') {
        expect(jsonDecode(req.body)['p_id'], 'n1');
        expect(jsonDecode(req.body)['p_device'], '收银台A');
        return json({
          'id': 'n1',
          'status': 'completed',
          'rev': 5,
          'updated_at': '2026-09-20T13:00:00Z',
          'data': localOrder(id: 'n1', closed: true).toJson(),
        });
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder(id: 'n1', closed: true, rev: 4)]);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    final after = s.pos.findOrder('n1')!;
    expect(after.status, OrderStatus.completed);
    expect(after.rev, 5);
    expect(after.dirty, isFalse);
    expect(
      s.seen.any((r) => r.url.path == '/rest/v1/orders' && r.method == 'POST'),
      isFalse,
      reason: '已结账的单走 RPC，不该再整单 upsert',
    );
  });

  test('RPC 说服务器上没这张单（离线开的+离线结的）→ 整单推上去', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/rpc/close_order') {
        return http.Response('null', 200);
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder(id: 'n1', closed: true, rev: 0)]);

    await s.sync.syncNow();

    expect(
      s.seen.any((r) => r.url.path == '/rest/v1/orders' && r.method == 'POST'),
      isTrue,
      reason: 'RPC 没找到就整单 upsert',
    );
    expect(s.sync.status.error, isNull);
  });

  test('网络/服务器出错：只记错误，不抛异常、本地单还是脏的（下次再推）', () async {
    final s = await setup((req) async {
      if (req.url.path == '/auth/v1/token') {
        return json({'access_token': 'AT', 'refresh_token': 'RT'});
      }
      return json({'message': 'boom'}, 500);
    });
    s.pos.adoptServerOrders([localOrder()]);

    await s.sync.syncNow(); // 不应该抛

    expect(s.sync.status.error, isNotNull);
    expect(s.pos.findOrder('n1')!.dirty, isTrue, reason: '推失败 → 还是脏的，下次重试');
    expect(s.sync.status.pendingOrders, 1);
  });

  test('登录失败（密码错）：错误信息留在状态里，收银不受影响', () async {
    final s = await setup((req) async {
      if (req.url.path == '/auth/v1/token') {
        return json({'error_description': 'Invalid login credentials'}, 400);
      }
      return defaultHandler(req);
    });

    await s.sync.syncNow();

    expect(s.sync.status.error, contains('Invalid login credentials'));
  });

  test('本地删掉的单：会真的从服务器删掉，而且**不会被下次同步又拉回来**', () async {
    final s = await setup((req) async {
      // 服务器上还留着这张单（还没删成功）→ 拉的时候不能把它塞回本地
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        return json([
          {
            'id': 'n1',
            'status': 'in_progress',
            'rev': 3,
            'updated_at': '2026-09-20T12:00:00Z',
            'data': localOrder(id: 'n1').toJson(),
          }
        ]);
      }
      if (req.url.path == '/rest/v1/orders' && req.method == 'DELETE') {
        expect(req.url.queryParameters['id'], 'in.(n1)');
        return http.Response('', 204);
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder(id: 'n1', rev: 3, dirty: false)]);
    s.pos.deleteOrder('n1');
    expect(s.pos.pendingDeletedIds, ['n1']);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(s.pos.pendingDeletedIds, isEmpty, reason: '删成功后清掉待删标记');
    expect(s.pos.findOrder('n1'), isNull,
        reason: '本地删掉的单不能被服务器那份又拉回来');
  });

  test('菜单：服务器没有 → 把本地的推上去，版本号存回本地', () async {
    final s = await setup(defaultHandler);
    s.pos.addMenuItem(sampleMenu.first);

    await s.sync.syncNow();

    final pushedMenu = s.seen
        .where((r) => r.url.path == '/rest/v1/menu' && r.method == 'POST')
        .toList();
    expect(pushedMenu, isNotEmpty);
    expect(s.settings.settings.menuVersion, 1);
    expect(s.settings.settings.menuDirty, isFalse);
  });

  test('菜单：服务器版本更高 → 拉下来覆盖本地', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/menu' && req.method == 'GET') {
        return json([
          {
            'version': 7,
            'updated_at': '2026-09-20T12:00:00Z',
            'data': {
              'categories': [
                {'id': 'c9', 'name': '后台加的类', 'emoji': '', 'colorValue': 0},
              ],
              'items': [
                {
                  'id': 'x9',
                  'name': '后台加的菜',
                  'price': 99,
                  'emoji': '',
                  'categoryId': 'c9',
                  'options': [],
                  'unit': '',
                }
              ],
            },
          }
        ]);
      }
      return defaultHandler(req);
    });

    await s.sync.syncNow();

    expect(s.pos.menu.map((m) => m.name), contains('后台加的菜'));
    expect(s.pos.categories.map((c) => c.name), contains('后台加的类'));
    expect(s.settings.settings.menuVersion, 7);
  });

  test('access token 过期（401）：自动重登一次再同步，不用人工干预', () async {
    var logins = 0;
    var orderPulls = 0;
    final s = await setup((req) async {
      if (req.url.path == '/auth/v1/token') {
        logins++;
        return json({'access_token': 'AT$logins', 'refresh_token': 'RT'});
      }
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        orderPulls++;
        // 第一趟说 token 过期；重登之后的第二趟就正常
        if (orderPulls == 1) {
          return json({'message': 'JWT expired', 'code': 'PGRST301'}, 401);
        }
        return json([]);
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder()]);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull, reason: '401 应该被自动处理掉');
    expect(logins, 2, reason: '第一趟 401 → 清会话重登 → 再试一趟');
    expect(orderPulls, 2);
    expect(s.pos.findOrder('n1')!.dirty, isFalse, reason: '重试成功后单子推上去了');
  });

  test('增量拉取：第一趟全量，之后只拉水位线之后改过的行', () async {
    var pulls = 0;
    final filters = <String?>[];
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        final q = req.url.queryParameters;
        if (q['select'] == 'id') {
          // 对账查询：把问到的单号原样回过去（说明它们都还在）
          final raw = (q['id'] ?? '').replaceAll('in.(', '').replaceAll(')', '');
          final ids = raw.split(',').where((e) => e.isNotEmpty);
          return json(ids.map((e) => {'id': e}).toList());
        }
        filters.add(q['updated_at']);
        pulls++;
        if (pulls == 1) {
          // 第一趟（全量）：服务器上有别的设备开的一张单
          return json([
            {
              'id': 'other-1',
              'status': 'in_progress',
              'rev': 2,
              'updated_at': '2026-09-20T12:00:00Z',
              'data': localOrder(id: 'other-1').toJson(),
            }
          ]);
        }
        return json([]); // 第二趟：没有新的改动
      }
      return defaultHandler(req);
    });

    await s.sync.syncNow();
    await s.sync.syncNow();

    expect(filters.length, 2);
    expect(filters.first, isNull, reason: '第一趟是全量（不带 updated_at 过滤）');
    expect(filters.last, 'gt.2026-09-20T11:59:55.000Z',
        reason: '第二趟只拉水位线之后的行（行的时间往前退 5 秒做重叠，不会漏）');
    expect(s.pos.findOrder('other-1'), isNotNull);
  });

  test('翻页：一次给不完（pageSize=2）时会把后面的行也拉回来', () async {
    final pages = <String?>[];
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        final q = req.url.queryParameters;
        if (q['select'] == 'id') {
          // 对账查询：把问到的单号原样回过去（说明它们都还在）
          final raw = (q['id'] ?? '').replaceAll('in.(', '').replaceAll(')', '');
          final ids = raw.split(',').where((e) => e.isNotEmpty);
          return json(ids.map((e) => {'id': e}).toList());
        }
        pages.add(q['offset']);
        final offset = int.tryParse(q['offset'] ?? '0') ?? 0;
        final all = [1, 2, 3]
            .map((i) => {
                  'id': 'r$i',
                  'status': 'in_progress',
                  'rev': 1,
                  'updated_at': '2026-09-20T12:0$i:00Z',
                  'data': localOrder(id: 'r$i').toJson(),
                })
            .toList();
        return json(all.skip(offset).take(2).toList());
      }
      return defaultHandler(req);
    }, pageSize: 2);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(pages, [null, '2'], reason: '第一页满了就接着拉第二页');
    expect(s.pos.findOrder('r1'), isNotNull);
    expect(s.pos.findOrder('r3'), isNotNull, reason: '第二页的行也要拉回来');
    expect(s.sync.status.pulled, 3);
  });

  test('别人删掉的进行中单：本地也跟着删；已结账的历史不动、也不重推', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        final q = req.url.queryParameters;
        // 对账查询：服务器上这些单全都已经没了（别的设备删掉了）
        if (q['select'] == 'id') return json([]);
        return json([]); // 拉取：没有任何改动
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([
      localOrder(id: 'gone', rev: 3, dirty: false),
      localOrder(id: 'done', rev: 3, dirty: false, closed: true),
    ]);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(s.pos.findOrder('gone'), isNull,
        reason: '别的设备删掉的进行中单，本机不能一直挂着（可能被再结一次账）');
    expect(s.pos.findOrder('done'), isNotNull,
        reason: '已结账的历史留在本机（日结要用），后台清老数据不能把它清掉');
    expect(
      s.seen.any((r) => r.url.path == '/rest/v1/orders' && r.method == 'POST'),
      isFalse,
      reason: '没改过的单不该被重推上去',
    );
  });

  test('推上去之后又加了菜、然后马上结账：RPC 的补丁要带上**新加的菜**', () async {
    Map<String, dynamic>? patch;
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/rpc/close_order') {
        patch = (jsonDecode(req.body)['p_patch'] as Map).cast<String, dynamic>();
        return json({
          'id': 'n1',
          'status': 'completed',
          'rev': 6,
          'updated_at': '2026-09-20T13:00:00Z',
          // 假服务器「自己那份」还是旧的（只有一道菜）——
          // 如果补丁里不带明细，采纳回来就会把新加的菜弄丢
          'data': localOrder(id: 'n1', closed: true, rev: 6).toJson(),
        });
      }
      return defaultHandler(req);
    });

    // 本地：这张单已经在服务器上了（rev=1），离线期间又加了一道菜，然后结账
    final synced = localOrder(id: 'n1', rev: 1, dirty: false);
    s.pos.adoptServerOrders([
      synced.copyWith(
        lines: [
          ...synced.lines,
          const OrderLine(name: '可乐', quantity: 2, unitPrice: 12),
        ],
        total: 52,
        status: OrderStatus.completed,
        closedAt: DateTime(2026, 9, 20, 13),
        paymentMethod: PaymentMethod.cash,
        dirty: true,
      ),
    ]);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(patch, isNotNull);
    expect(patch!['status'], 'completed');
    expect(patch!['lines'], hasLength(2),
        reason: '结账补丁必须带上整份明细，否则新加的菜会凭空消失');
  });

  test('推送请求还在路上时本地又改了这张单 → 不能被服务器的回包盖掉', () async {
    late TestRig s;
    var edited = false;
    s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'POST') {
        if (!edited) {
          edited = true;
          // 假装「请求还在路上时，收银员把第一道菜改成了 2 份」
          s.pos.changeOrderLineQuantity('n1', 0, 1);
        }
        final rows = (jsonDecode(req.body) as List).cast<Map>();
        return json(rows
            .map((r) => {
                  ...r.cast<String, dynamic>(),
                  'rev': 1,
                  'updated_at': '2026-09-20T12:00:00Z',
                })
            .toList());
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder()]); // 1 份、脏的
    expect(s.pos.findOrder('n1')!.lines.first.quantity, 1);

    await s.sync.syncNow();

    final after = s.pos.findOrder('n1')!;
    expect(after.lines.first.quantity, 2,
        reason: '推送期间刚改的那一份，不能被服务器回包里那份旧数据盖掉');
    expect(after.dirty, isTrue, reason: '还是脏的 → 下一次同步会把新版本再推一遍');
  });

  test('改菜单：防抖一下再推（连改多次也只推一趟，到点一定会推）', () async {
    final s = await setup(defaultHandler);
    // 生产代码里这两个钩子是 app.dart 接上的，这里手动接一下（模拟真实情况）
    s.pos.onMenuChanged = s.sync.onLocalMenuChanged;
    int menuPosts() => s.seen
        .where((r) => r.url.path == '/rest/v1/menu' && r.method == 'POST')
        .length;

    // 连着改两次菜单（模拟 Excel 导入 / 一条条改菜）
    s.pos.addMenuItem(sampleMenu.first);
    s.pos.addMenuItem(sampleMenu[1]);
    expect(menuPosts(), 0, reason: '刚改完不会立刻发请求（防抖 2 秒）');
    expect(s.sync.menuPending, isTrue, reason: '设置页要能显示「菜单待上传」');

    await Future<void>.delayed(const Duration(seconds: 3));

    expect(menuPosts(), 1, reason: '防抖到点后推一趟，而且只推一趟');
    expect(s.settings.settings.menuDirty, isFalse);
    expect(s.sync.menuPending, isFalse);
  });

  test('没开开关 / 没填全：能说清「为什么同步不了」（不再静默什么都不做）', () async {
    final s = await setup(defaultHandler);

    await s.settings.updateSync((x) => x.syncEnabled = false);
    expect(s.sync.syncBlockedReason, 'sync.blockedDisabled');

    await s.settings.updateSync((x) => x.syncEnabled = true);
    expect(s.sync.syncBlockedReason, isNull, reason: '都填好了 → 没有理由拦着');

    await s.settings.updateSync((x) => x.syncPassword = '');
    expect(s.sync.syncBlockedReason, 'sync.blockedPassword');

    await s.settings.updateSync((x) => x.syncPassword = 'pw');
    await s.settings.updateSync((x) => x.supabaseUrl = '');
    expect(s.sync.syncBlockedReason, 'sync.blockedUrl');

    await s.settings.updateSync((x) => x.supabaseUrl = 'https://demo.supabase.co');
    await s.settings.updateSync((x) => x.supabaseAnonKey = '');
    expect(s.sync.syncBlockedReason, 'sync.blockedKey');

    await s.settings.updateSync((x) => x.supabaseAnonKey = 'anon');
    await s.settings.updateSync((x) => x.syncEmail = '');
    expect(s.sync.syncBlockedReason, 'sync.blockedEmail');

    // 而且「拦着」的时候真的一张都不发
    s.seen.clear();
    await s.sync.syncNow();
    expect(s.seen, isEmpty);
  });

  test('close_order 回一行「全 NULL」→ 整单推上去（结完账的单不能上不了后台）', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/rpc/close_order') {
        // PostgREST 对「函数返回 NULL 组合类型」的一种真实写法
        return json({
          'id': null,
          'status': null,
          'rev': null,
          'updated_at': null,
          'data': null,
        });
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder(id: 'n1', closed: true, rev: 0, dirty: true)]);

    await s.sync.syncNow();

    expect(s.sync.status.error, isNull);
    expect(
      s.seen.any((r) => r.url.path == '/rest/v1/orders' && r.method == 'POST'),
      isTrue,
      reason: '回包不行就整单 upsert —— 这是「结了一单但后台没有」那个 bug 的回归',
    );
    expect(s.pos.findOrder('n1')!.dirty, isFalse, reason: '推成功 → 不再是脏的');
  });

  test('服务器上有一张坏单：跳过它，别的照样同步（不再一按就报错）', () async {
    final s = await setup((req) async {
      if (req.url.path == '/rest/v1/orders' && req.method == 'GET') {
        final q = req.url.queryParameters;
        if (q['select'] == 'id') return json([]); // 对账：没问出什么
        // 服务器上有一行「数据不完整」的单（data 里少了 createdAt / lines）
        return json([
          {
            'id': 'bad-1',
            'status': 'in_progress',
            'rev': 2,
            'updated_at': '2026-09-20T12:05:00Z',
            'data': {'id': 'bad-1'},
          }
        ]);
      }
      return defaultHandler(req);
    });
    s.pos.adoptServerOrders([localOrder()]); // 本地一张脏单，要照常推上去

    await s.sync.syncNow();

    expect(s.sync.status.error, contains('(1)'),
        reason: '提醒「有 1 张坏数据被跳过」，而不是直接失败');
    expect(s.pos.findOrder('bad-1'), isNull, reason: '坏的那张不能塞进本地');
    expect(s.pos.findOrder('n1')!.dirty, isFalse,
        reason: '别的单照常推上去了（这才是重点）');
    expect(s.sync.status.pushed, 1);
  });

  test('没启用同步 / 没配置好 → 一次请求都不发', () async {
    final s = await setup(defaultHandler);
    // 先关掉开关
    await s.settings.updateSync((x) => x.syncEnabled = false);
    await s.sync.syncNow();
    expect(s.seen, isEmpty);

    // 开关打开但地址被清空 → 还是不发
    await s.settings.updateSync((x) {
      x.syncEnabled = true;
      x.supabaseUrl = '';
    });
    await s.sync.syncNow();
    expect(s.seen, isEmpty);
  });
}
