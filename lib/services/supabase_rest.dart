import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supabase 的报错（登录失败 / 权限 / 网络）。
class SupabaseError implements Exception {
  final String message;
  final int? statusCode;

  const SupabaseError(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// 直连 Supabase 的**极简客户端**：只做我们要的两件事 ——
/// 登录（GoTrue）和读写表（PostgREST）。
///
/// 为什么不用 `supabase_flutter` 包：
/// - 我们只需要 4 个接口（登录 / 刷新 / 查 / upsert + 一个 RPC），
///   自己写 100 多行就够了，依赖少、出问题好查；
/// - `http.Client` 可以注入 → **单元测试用 MockClient 就能盯住每个请求**（不用真联网）。
///
/// 用到的 Supabase 接口（都是公开的 HTTP API）：
/// - 登录：`POST {url}/auth/v1/token?grant_type=password`
/// - 刷新：`POST {url}/auth/v1/token?grant_type=refresh_token`
/// - 查表：`GET  {url}/rest/v1/{table}?select=*&...`
/// - upsert：`POST {url}/rest/v1/{table}` + `Prefer: resolution=merge-duplicates`
/// - 函数：`POST {url}/rest/v1/rpc/{fn}`
class SupabaseRest {
  /// 例如 `https://abcdefg.supabase.co`（不要带结尾的 `/`）。
  final String url;

  /// 项目里的 **anon public** key（公开的，可以放在设备上）。
  final String anonKey;

  final http.Client _http;

  String? _accessToken;
  String? _refreshToken;

  /// 最近一次响应里的**服务器时间**（HTTP `Date` 头，秒级）。
  ///
  /// 为什么要它：增量拉取的水位线必须是**服务器时间**，
  /// 用本机时钟的话，设备时间快了/慢了就会漏拉或者重复拉。
  DateTime? _serverTime;
  DateTime? get lastServerTime => _serverTime;

  SupabaseRest({
    required String url,
    required String anonKey,
    http.Client? httpClient,
  })  : url = SupabaseRest.normalizeUrl(url),
        anonKey = anonKey.trim(),
        _http = httpClient ?? http.Client();

  /// 把用户填的地址整理成干净的 origin —— 设置页里手填/粘贴的地址什么形态都有：
  ///
  /// - `xxxxxxxx.supabase.co`（**没写协议头**，最常见）→ 补上 `https://`；
  /// - 结尾多打的 `/`（甚至 `//`）→ 去掉；
  /// - 从文档里复制时常常带上 `/rest/v1` → 去掉（不然我们会拼成
  ///   `…/rest/v1/rest/v1/orders`，一堆 404）。
  ///
  /// **注意**：这个方法要跟 [SyncService] 里「判断要不要重建客户端」的比较用**同一个**
  /// —— 两边规则不一致的话，每趟同步都会重建客户端、把登录态丢掉，变成每次都要重登。
  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) {
      u = 'https://$u';
    }
    u = u.replaceAll(RegExp(r'/+$'), '');
    u = u.replaceAll(RegExp(r'/rest/v1$', caseSensitive: false), '');
    u = u.replaceAll(RegExp(r'/+$'), '');
    return u;
  }

  /// 已经登录（或刷新过）了吗。
  bool get hasSession => _accessToken != null;

  /// 忘掉当前会话（token 过期 / 401 时用：下次会自动重新登录）。
  void clearSession() {
    _accessToken = null;
    _refreshToken = null;
  }

  /// 刷新用的 token（存到本机，下次启动可以直接续上，不用重新输密码）。
  String? get refreshToken => _refreshToken;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  Map<String, String> _headers({bool auth = true, String? prefer}) => {
        'apikey': anonKey,
        'Content-Type': 'application/json',
        if (auth && _accessToken != null)
          'Authorization': 'Bearer $_accessToken',
        if (prefer != null) 'Prefer': prefer,
      };

  /// 邮箱 + 密码登录。
  Future<void> signIn(String email, String password) async {
    _requireConfig();
    final res = await _http.post(
      Uri.parse('$url/auth/v1/token?grant_type=password'),
      headers: _headers(auth: false),
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    _readSession(res, what: '登录');
  }

  /// 用上次存下来的 refresh token 续上会话（App 重启后调）。
  Future<void> refreshSession(String refreshToken) async {
    _requireConfig();
    final res = await _http.post(
      Uri.parse('$url/auth/v1/token?grant_type=refresh_token'),
      headers: _headers(auth: false),
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    _readSession(res, what: '刷新登录');
  }

  void _readSession(http.Response res, {required String what}) {
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw SupabaseError(
        '$what失败：${body is Map ? (body['error_description'] ?? body['msg'] ?? body['error'] ?? res.body) : res.body}',
        statusCode: res.statusCode,
      );
    }
    _accessToken = (body is Map ? body['access_token'] : null)?.toString();
    final refresh = (body is Map ? body['refresh_token'] : null)?.toString();
    if (refresh != null && refresh.isNotEmpty) _refreshToken = refresh;
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw SupabaseError('$what失败：服务器没返回 access_token');
    }
  }

  /// 查表：`select` 例如 `*` 或 `id,rev,updated_at,status,data`；
  /// [filters] 是 PostgREST 的查询参数，例如 `{'updated_at': 'gt.2026-01-01T00:00:00Z'}`；
  /// [limit] / [offset] 用来**翻页**（Supabase 默认一次最多给 1000 行）。
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String select = '*',
    Map<String, String> filters = const {},
    String? order,
    int? limit,
    int? offset,
  }) async {
    _requireConfig();
    final q = <String, String>{'select': select, ...filters};
    if (order != null) q['order'] = order;
    if (limit != null) q['limit'] = '$limit';
    if (offset != null && offset > 0) q['offset'] = '$offset';
    final uri = Uri.parse('$url/rest/v1/$table').replace(queryParameters: q);
    final res = await _http.get(uri, headers: _headers());
    _noteServerTime(res);
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw SupabaseError(_errorText(body, res), statusCode: res.statusCode);
    }
    if (body is! List) throw const SupabaseError('查表返回的不是列表');
    return body
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// upsert（按主键 id 冲突就更新），返回服务器上**最终的行**（含 rev/updated_at）。
  Future<List<Map<String, dynamic>>> upsert(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    _requireConfig();
    if (rows.isEmpty) return const [];
    final uri = Uri.parse('$url/rest/v1/$table');
    final res = await _http.post(
      uri,
      headers: _headers(prefer: 'resolution=merge-duplicates,return=representation'),
      body: jsonEncode(rows),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw SupabaseError(_errorText(body, res), statusCode: res.statusCode);
    }
    if (body is! List) return const [];
    return body.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// 删行：`filters` 例如 `{'id': 'in.(a,b)'}`（PostgREST 的过滤语法）。
  Future<void> delete(String table, Map<String, String> filters) async {
    _requireConfig();
    if (filters.isEmpty) {
      throw const SupabaseError('删行必须带过滤条件（防止把整张表删空）');
    }
    final uri =
        Uri.parse('$url/rest/v1/$table').replace(queryParameters: filters);
    final res = await _http.delete(uri, headers: _headers());
    if (res.statusCode >= 400) {
      throw SupabaseError(_errorText(_decode(res), res),
          statusCode: res.statusCode);
    }
  }

  /// 调一个数据库函数（我们只用了 `close_order`）。
  ///
  /// ⚠️ 返回 `null` 表示「服务器上**没有**这一行」，调用方要按「整单推上去」处理。
  /// 这里要认出**三种**「没有」的写法，它们都会真实出现：
  ///
  /// 1. 响应体是 JSON `null`（函数返回了 NULL 组合类型）；
  /// 2. 响应体是 `[{"id":null,"status":null,…}]` —— PostgREST 把「一行全 NULL」的
  ///    组合类型包成数组返回；
  /// 3. 响应体是 `{"id":null,…}` 这种**一行全 NULL 的对象**（不同版本/网关的差别）。
  ///
  /// 第 2、3 种如果不识别，就会把一个「全 null 的行」当成正常返回 →
  /// 上层拿去 `Order.fromJson` 直接抛
  /// `type 'NULL' is not a subtype of type 'String' in type cast`，
  /// 而且**再也不会走「整单推上去」那条路** → 结完账的单永远上不了后台。
  Future<Map<String, dynamic>?> rpc(
    String fn,
    Map<String, dynamic> args,
  ) async {
    _requireConfig();
    final uri = Uri.parse('$url/rest/v1/rpc/$fn');
    final res = await _http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(args),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw SupabaseError(_errorText(body, res), statusCode: res.statusCode);
    }
    final row = _firstRow(body);
    if (row == null) return null;
    // 主键是空的 → 这行根本不存在（全 NULL 的那三种情况）
    if ((row['id'] ?? '').toString().isEmpty) return null;
    return row;
  }

  /// 从响应体里取「第一行」：对象直接用，数组取第一个（PostgREST 有时包一层数组）。
  static Map<String, dynamic>? _firstRow(dynamic body) {
    if (body is Map) return body.cast<String, dynamic>();
    if (body is List && body.isNotEmpty && body.first is Map) {
      return (body.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  /// 服务器时间（用来显示「连接成功」和校准增量同步的时间点）。
  Future<DateTime> serverTime() async {
    final rows = await select('orders', select: 'updated_at', order: 'updated_at.desc', limit: 1);
    if (rows.isEmpty) return DateTime.now();
    return DateTime.tryParse((rows.first['updated_at'] ?? '').toString()) ??
        DateTime.now();
  }

  void close() => _http.close();

  /// 记下响应头里的服务器时间（`Date: Wed, 21 Oct 2015 07:28:00 GMT`）。
  /// 没有这个头就保持上一次的值（不要用本机时钟去猜）。
  void _noteServerTime(http.Response res) {
    final raw = _header(res, 'date');
    if (raw == null) return;
    final t = parseHttpDate(raw);
    if (t != null) _serverTime = t;
  }

  static const Map<String, int> _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// 解析 HTTP 的 `Date` 响应头（`Wed, 21 Oct 2015 07:28:00 GMT`）。
  ///
  /// ⚠️ **不能直接用 `DateTime.parse`**：它只认 ISO 8601 那一套，
  /// 不认这种「带星期几 + GMT」的 HTTP 日期格式 —— `DateTime.tryParse` 会返回
  /// null，于是服务器时间永远是 null（这个坑是测试里撞出来的：断言
  /// `lastServerTime` 得到 `Actual: <null>`）。所以这里自己解析。
  ///
  /// 顺手也接受 ISO 串（有些代理/自建网关会给 `2026-09-20T12:00:00Z`），
  /// 服务器给什么格式都能用。
  static DateTime? parseHttpDate(String raw) {
    final s = raw.trim();
    // 用具名分组（用序号的话很容易数错：这里的顺序是 日 / 月名 / 年 / 时 / 分 / 秒）
    final m = RegExp(r'^\w{3}, (?<day>\d{2}) (?<mon>\w{3}) (?<year>\d{4}) '
            r'(?<h>\d{2}):(?<min>\d{2}):(?<sec>\d{2}) GMT$')
        .firstMatch(s);
    if (m != null) {
      final month = _months[m.namedGroup('mon')];
      if (month != null) {
        return DateTime.utc(
          int.parse(m.namedGroup('year')!),
          month,
          int.parse(m.namedGroup('day')!),
          int.parse(m.namedGroup('h')!),
          int.parse(m.namedGroup('min')!),
          int.parse(m.namedGroup('sec')!),
        );
      }
    }
    return DateTime.tryParse(s)?.toUtc(); // 兜底：ISO 8601
  }

  /// 读一个响应头（不区分大小写：dart:io 会给小写的键，但别的 client 不一定）。
  static String? _header(http.Response res, String name) {
    final direct = res.headers[name];
    if (direct != null) return direct;
    for (final e in res.headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  void _requireConfig() {
    if (!isConfigured) {
      throw const SupabaseError('还没填后台地址（Supabase URL / anon key）');
    }
  }

  dynamic _decode(http.Response res) {
    if (res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  String _errorText(dynamic body, http.Response res) {
    if (body is Map) {
      return (body['message'] ?? body['msg'] ?? body['error_description'] ?? res.body)
          .toString();
    }
    return res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body;
  }
}
