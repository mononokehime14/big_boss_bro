import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:big_boss_bro/services/supabase_rest.dart';

/// Supabase 客户端的**请求形状**测试：用 MockClient 拦请求，不联网。
///
/// 盯三件事：
/// 1. 登录时 url / 头（apikey）/ body 对不对，token 有没有存下来；
/// 2. 读写表时的查询串、`Prefer: resolution=merge-duplicates` 有没有带；
/// 3. 服务器返回错误时，抛出的是带原因的 [SupabaseError]（界面能显示给用户看）。
void main() {
  SupabaseRest client(
    Future<http.Response> Function(http.Request req) handler, {
    String url = 'https://demo.supabase.co',
    String key = 'anon-key',
  }) =>
      SupabaseRest(
        url: url,
        anonKey: key,
        httpClient: MockClient(handler),
      );

  http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  /// 假服务器的**登录响应**：每个 handler 都得先处理 `/auth/v1/token`。
  ///
  /// 不处理的话，`signIn()` 拿到的是「表数据」那种 JSON（没有 `access_token`），
  /// 会直接抛「登录失败：服务器没返回 access_token」—— 测试还没跑到正题就挂了。
  /// 返回 null 表示「这不是登录请求，你自己接着处理」。
  http.Response? loginOk(http.Request req) => req.url.path == '/auth/v1/token'
      ? json({'access_token': 'AT', 'refresh_token': 'RT'})
      : null;

  test('没填地址就先报错（不会发请求）', () async {
    final c = client((_) async => json({'ok': true}), url: '', key: '');
    expect(c.isConfigured, isFalse);
    expect(() => c.signIn('a@b.c', 'x'), throwsA(isA<SupabaseError>()));
  });

  test('登录：url / apikey / body 正确，token 存下来', () async {
    late http.Request seen;
    final c = client((req) async {
      seen = req;
      return json({
        'access_token': 'AT',
        'refresh_token': 'RT',
        'user': {'email': 'device1@bossbro.local'},
      });
    });

    await c.signIn('device1@bossbro.local', 'pw');

    expect(seen.url.toString(),
        'https://demo.supabase.co/auth/v1/token?grant_type=password');
    expect(seen.method, 'POST');
    expect(seen.headers['apikey'], 'anon-key');
    expect(jsonDecode(seen.body),
        {'email': 'device1@bossbro.local', 'password': 'pw'});
    expect(c.hasSession, isTrue);
    expect(c.refreshToken, 'RT');
  });

  test('登录失败：抛出带服务器原因的 SupabaseError', () async {
    final c = client((_) async =>
        json({'error_description': 'Invalid login credentials'}, 400));
    expect(
      () => c.signIn('a@b.c', 'bad'),
      throwsA(isA<SupabaseError>().having(
          (e) => e.message, 'message', contains('Invalid login credentials'))),
    );
  });

  test('刷新登录：用 refresh_token 续上会话', () async {
    late http.Request seen;
    final c = client((req) async {
      seen = req;
      return json({'access_token': 'AT2', 'refresh_token': 'RT2'});
    });
    await c.refreshSession('RT1');
    expect(seen.url.toString(),
        'https://demo.supabase.co/auth/v1/token?grant_type=refresh_token');
    expect(jsonDecode(seen.body), {'refresh_token': 'RT1'});
    expect(c.hasSession, isTrue);
  });

  test('查表：带 select / 过滤 / 排序 / 上限，并带 Bearer token', () async {
    late http.Request seen;
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      seen = req;
      return json([
        {
          'id': 'n1',
          'status': 'in_progress',
          'rev': 3,
          'updated_at': '2026-09-20T12:05:00Z',
          'data': {'id': 'n1'},
        }
      ]);
    });
    // 先登录（否则 select 没有 token —— 我们的实现允许无 token 查，但服务器会拒绝）
    await c.signIn('a@b.c', 'pw');
    final rows = await c.select(
      'orders',
      select: 'id,rev,updated_at,status,data',
      filters: {'updated_at': 'gt.2026-09-20T12:00:00Z'},
      order: 'updated_at.asc',
      limit: 100,
    );

    expect(seen.url.path, '/rest/v1/orders');
    final q = seen.url.queryParameters;
    expect(q['select'], 'id,rev,updated_at,status,data');
    expect(q['updated_at'], 'gt.2026-09-20T12:00:00Z');
    expect(q['order'], 'updated_at.asc');
    expect(q['limit'], '100');
    expect(seen.headers['Authorization'], 'Bearer AT');
    expect(rows.length, 1);
    expect(rows.first['id'], 'n1');
  });

  test('upsert：带 merge-duplicates，返回服务器那几行', () async {
    late http.Request seen;
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      seen = req;
      return json([
        {'id': 'n1', 'rev': 4, 'updated_at': '2026-09-20T12:10:00Z', 'data': {}}
      ]);
    });
    await c.signIn('a@b.c', 'pw');
    final back = await c.upsert('orders', [
      {'id': 'n1', 'status': 'in_progress', 'data': {'id': 'n1'}},
    ]);

    expect(seen.method, 'POST');
    expect(seen.url.path, '/rest/v1/orders');
    expect(seen.headers['Prefer'],
        contains('resolution=merge-duplicates'));
    expect(seen.headers['Prefer'], contains('return=representation'));
    expect(back.first['rev'], 4);
  });

  test('upsert 空列表：直接返回，不发请求', () async {
    var called = false;
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      called = true;
      return json([]);
    });
    await c.signIn('a@b.c', 'pw');
    called = false; // 登录那一次当然发过请求，从这里才开始算
    expect(await c.upsert('orders', []), isEmpty);
    expect(called, isFalse);
  });

  test('RPC close_order：参数名和返回都对', () async {
    late http.Request seen;
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      seen = req;
      return json({
        'id': 'n1',
        'status': 'completed',
        'rev': 5,
        'updated_at': '2026-09-20T12:20:00Z',
        'data': {'id': 'n1'},
      });
    });
    await c.signIn('a@b.c', 'pw');
    final row = await c.rpc('close_order', {
      'p_id': 'n1',
      'p_patch': {'status': 'completed'},
      'p_device': '收银台A',
    });

    expect(seen.url.path, '/rest/v1/rpc/close_order');
    expect(jsonDecode(seen.body)['p_id'], 'n1');
    expect(row?['status'], 'completed');
  });

  test('RPC 返回 null（服务器上没这张单）→ 返回 null，让上层整单推上去', () async {
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      return http.Response('null', 200);
    });
    await c.signIn('a@b.c', 'pw');
    expect(await c.rpc('close_order', {'p_id': 'nope'}), isNull);
  });

  test('RPC 返回「一行全 NULL」→ 当成「服务器上没这张单」（返回 null）', () async {
    // PostgREST 对「函数返回 NULL 组合类型」有几种真实写法，都得认出来。
    // 认不出来的话，上层会把这个「全 null 的行」拿去解析 → 抛类型错误，
    // 而且**再也不会走「整单推上去」** → 结完账的单永远上不了后台（真实踩过）。
    for (final body in <Object?>[
      null,
      {'id': null, 'status': null, 'rev': null, 'updated_at': null, 'data': null},
      [
        {'id': null, 'status': null, 'data': null}
      ],
    ]) {
      final c = client((req) async {
        final login = loginOk(req);
        if (login != null) return login;
        return json(body);
      });
      await c.signIn('a@b.c', 'pw');
      expect(await c.rpc('close_order', {'p_id': 'nope'}), isNull,
          reason: 'body=$body 应该被当成「没有这一行」');
    }
  });

  test('RPC 把单行包成数组 → 也能认出来（取第一行）', () async {
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      return json([
        {
          'id': 'n1',
          'status': 'completed',
          'rev': 5,
          'updated_at': '2026-09-20T12:20:00Z',
          'data': {'id': 'n1'},
        }
      ]);
    });
    await c.signIn('a@b.c', 'pw');
    final row = await c.rpc('close_order', {'p_id': 'n1'});
    expect(row?['id'], 'n1');
    expect(row?['status'], 'completed');
  });

  test('表操作失败：带 HTTP 状态和服务器消息', () async {
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      return json({'message': 'new row violates row-level security policy'}, 401);
    });
    await c.signIn('a@b.c', 'pw');
    expect(
      () => c.upsert('orders', [
        {'id': 'x'}
      ]),
      throwsA(isA<SupabaseError>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', contains('row-level security'))),
    );
  });

  test('HTTP Date 头能解析（DateTime.parse 不认这种格式，所以自己解析）', () {
    expect(SupabaseRest.parseHttpDate('Sun, 20 Sep 2026 12:00:00 GMT'),
        DateTime.utc(2026, 9, 20, 12, 0, 0));
    expect(SupabaseRest.parseHttpDate('Wed, 21 Oct 2015 07:28:00 GMT'),
        DateTime.utc(2015, 10, 21, 7, 28, 0));
    // 顺手也认 ISO（有些网关给的是这种）
    expect(SupabaseRest.parseHttpDate('2026-09-20T12:00:00Z'),
        DateTime.utc(2026, 9, 20, 12));
    // 乱七八糟的 → null，不抛异常
    expect(SupabaseRest.parseHttpDate('不是时间'), isNull);
  });

  test('翻页 offset + 响应头里的服务器时间（增量拉取的水位线要用）', () async {
    // 先确认「响应头确实带得上」（名字大小写都认）——
    // 免得将来挂了分不清是「取头」还是「解析」那一层的问题。
    final probe = http.Response.bytes(utf8.encode('[]'), 200,
        headers: {'Date': 'Sun, 20 Sep 2026 12:00:00 GMT'});
    expect(probe.headers.keys.map((k) => k.toLowerCase()), contains('date'));

    late http.Request seen;
    final c = client((req) async {
      final login = loginOk(req);
      if (login != null) return login;
      seen = req;
      return http.Response.bytes(
        utf8.encode('[]'),
        200,
        headers: {
          'content-type': 'application/json',
          // 故意用大写的键：我们的取头是真·不区分大小写的
          'Date': 'Sun, 20 Sep 2026 12:00:00 GMT',
        },
      );
    });
    await c.signIn('a@b.c', 'pw');

    await c.select('orders', limit: 1000, offset: 2000);
    expect(seen.url.queryParameters['limit'], '1000');
    expect(seen.url.queryParameters['offset'], '2000');
    expect(c.lastServerTime, DateTime.utc(2026, 9, 20, 12, 0, 0));

    // offset=0 不用拼进查询串（第一页）
    await c.select('orders', limit: 1000, offset: 0);
    expect(seen.url.queryParameters.containsKey('offset'), isFalse);
  });

  test('地址结尾多个斜杠也能用', () async {
    late http.Request seen;
    final c = client(
      (req) async {
        seen = req;
        return json({'access_token': 'AT'});
      },
      url: 'https://demo.supabase.co//',
    );
    await c.signIn('a@b.c', 'pw');
    expect(seen.url.toString(),
        'https://demo.supabase.co/auth/v1/token?grant_type=password');
  });

  test('地址整理：没写协议头补 https、带上 /rest/v1 也认得', () {
    expect(SupabaseRest.normalizeUrl('demo.supabase.co'),
        'https://demo.supabase.co');
    expect(SupabaseRest.normalizeUrl('  https://demo.supabase.co/  '),
        'https://demo.supabase.co');
    // 从 Supabase 文档里复制常常带着这一段
    expect(SupabaseRest.normalizeUrl('https://demo.supabase.co/rest/v1'),
        'https://demo.supabase.co');
    expect(SupabaseRest.normalizeUrl('http://127.0.0.1:8000/rest/v1/'),
        'http://127.0.0.1:8000');
    expect(SupabaseRest.normalizeUrl(''), '');
  });

  test('地址没写协议头也能真的发出去（不会抛 URI 错）', () async {
    late http.Request seen;
    final c = client(
      (req) async {
        seen = req;
        return json({'access_token': 'AT'});
      },
      url: 'demo.supabase.co',
    );
    await c.signIn('a@b.c', 'pw');
    expect(seen.url.scheme, 'https');
    expect(seen.url.host, 'demo.supabase.co');
  });
}
