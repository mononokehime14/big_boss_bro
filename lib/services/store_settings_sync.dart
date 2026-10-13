import 'dart:convert';

import '../data/settings_store.dart';

/// **店级配置同步的纯逻辑**（不碰网络、不碰界面 → 好写单测）。
///
/// 背景：订单 / 菜单 / 员工考勤早就会同步了，但**「这家店怎么配置」**一直只存在本机 ——
/// 于是换一台新设备（比如新装的平板）就得从头再填一遍店名、地址、税率、货币、
/// 桌号、各分类的常用备注……这明显不对：那是**整店共用**的东西。
///
/// 所以这里把「店级配置」也按 `menu` 那套做成服务器上的一行：
/// 表 `store_settings`，永远只有一行 `id = 'current'`，整份 JSON + 版本号。
///
/// **哪些同步、哪些不同步**：
/// - 同步（整店共用）：店名、店头（地址/电话/RFC）、税率与含税方式、货币符号与汇率、
///   桌号清单、各分类的常用备注、日结支出、菜品管理密码；
/// - **不同步**（每台设备自己的硬件/偏好）：打印机地址、端口、Windows 打印机名、
///   纸宽、小票编码、Font A、厨师单字号、小票语言、点单排序、后台账号与设备名。
///   理由：平板和收银电脑接的是**不同的打印机**，把蓝牙 MAC 同步过去只会把对方搞坏。
class StoreSettingsSync {
  const StoreSettingsSync._();

  /// 服务器上永远是这一行。
  static const String rowId = 'current';

  /// 要同步的字段 → 服务器那一行的 `data`。
  ///
  /// ⚠️ 这个 map 的**键顺序是固定的**（Dart 的 map 字面量保持插入顺序），
  /// 而 [encode] 直接 `jsonEncode` 它 —— 所以同一个设置永远得到同一个字符串，
  /// 这样就可以**用字符串比较**判断「本机改过没有」（见 [encode]）。
  /// 改这个 map 的时候**加在末尾**，否则所有设备都会被判定为"改过"而各推一次。
  static Map<String, dynamic> toData(Settings s) => <String, dynamic>{
        'storeName': s.storeName,
        'storeHeader': s.storeHeader,
        'currencySymbol': s.currencySymbol,
        'baseCurrency': s.baseCurrency,
        'exchangeRates': s.exchangeRates,
        'taxRate': s.taxRate,
        'taxIncluded': s.taxIncluded,
        'tables': s.tables,
        'notesByCategory': s.notesByCategory,
        'dailyExpenses': s.dailyExpenses,
        'menuPassword': s.menuPassword,
      };

  /// 稳定的 JSON 字符串：本机有没有改过，就靠「现在这份」和「上次同步的那份」比。
  static String encode(Settings s) => jsonEncode(toData(s));

  /// 本机配置 → 要写进 `store_settings` 那一行的字段。
  ///
  /// 注意**不送** `version` / `updated_at`：那两个由数据库的触发器维护，
  /// 设备送什么都不算（跟 `menu` / `attendance_staff` 一个规矩）。
  static Map<String, dynamic> toRow(Settings s, {required String deviceId}) =>
      <String, dynamic>{
        'id': rowId,
        'device_id': deviceId,
        'data': toData(s),
      };

  /// 服务器那一行的 `data`（不是对象 / 缺失 → null，调用方跳过这一趟就行）。
  static Map<String, dynamic>? dataFromRow(Map<String, dynamic> row) {
    final data = row['data'];
    if (data is! Map) return null;
    return data.cast<String, dynamic>();
  }

  /// 服务器那份配置 → 写回本机 [Settings]。
  ///
  /// **只覆盖店级字段**，打印机/纸宽/小票编码/后台账号那些本机专属的**一个字都不动**。
  /// 每一项都容错：缺了、类型不对就保持本机原值（服务器上的数据被人手改过也不至于崩）。
  static void applyTo(Settings s, Map<String, dynamic> data) {
    final name = _str(data['storeName']);
    if (name != null) s.storeName = name;

    final header = _str(data['storeHeader']);
    if (header != null) s.storeHeader = header;

    final symbol = _str(data['currencySymbol']);
    if (symbol != null && symbol.trim().isNotEmpty) {
      s.currencySymbol = symbol;
    }

    final base = _str(data['baseCurrency']);
    if (base != null && base.trim().isNotEmpty) s.baseCurrency = base.trim();

    final rates = _numMap(data['exchangeRates']);
    if (rates != null) s.exchangeRates = rates;

    final tax = _num(data['taxRate']);
    if (tax != null) s.taxRate = tax < 0 ? 0 : tax;

    final taxIncluded = _bool(data['taxIncluded']);
    if (taxIncluded != null) s.taxIncluded = taxIncluded;

    final tables = _strList(data['tables']);
    // 空桌号清单没有意义（本机加载时也会兜回默认值）→ 空就保持本机原值
    if (tables != null && tables.isNotEmpty) s.tables = tables;

    final notes = _notes(data['notesByCategory']);
    if (notes != null) s.notesByCategory = notes;

    final expenses = _numMap(data['dailyExpenses']);
    if (expenses != null) s.dailyExpenses = expenses;

    final password = _str(data['menuPassword']);
    if (password != null && password.trim().isNotEmpty) {
      s.menuPassword = password.trim();
    }
  }

  /// 本机配置**还是不是出厂默认值**？
  ///
  /// 用途：服务器上还没有店级配置时，只有「本机真的配置过」的设备才把它当作云端初始值推上去。
  /// 这样**新装的设备（全是默认值）不会抢先把自己的默认配置写成云端配置**，
  /// 把老设备真正的店名/备注覆盖掉 —— 那种顺序反过来的情况（先跑平板、后跑收银机）
  /// 靠这一条就不至于造成损失。
  static bool isPristine(Settings s) =>
      (s.storeName.trim().isEmpty || s.storeName.trim() == kDefaultStoreName) &&
      s.storeHeader.trim().isEmpty &&
      s.taxRate == 0 &&
      s.notesByCategory.values.every((list) => list.isEmpty) &&
      s.dailyExpenses.isEmpty &&
      _sameList(s.tables, Settings.defaultTables);

  /// 本机配置和「上次同步的那份」是不是一样（一样 = 没有本机改动要推）。
  ///
  /// [lastSyncedJson] 为空表示**这台设备从来没同步过店级配置** ——
  /// 这时**不算改过**，让服务器那份说了算（新设备第一次接入就走这条路）。
  static bool hasLocalChanges(Settings s, String lastSyncedJson) =>
      lastSyncedJson.isNotEmpty && encode(s) != lastSyncedJson;

  // ---------------- 容错取值 ----------------

  static String? _str(dynamic v) => v is String ? v : null;

  static bool? _bool(dynamic v) => v is bool ? v : null;

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  static List<String>? _strList(dynamic v) {
    if (v is! List) return null;
    return v
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  static Map<String, double>? _numMap(dynamic v) {
    if (v is! Map) return null;
    final out = <String, double>{};
    v.forEach((key, value) {
      if (value is num) out[key.toString()] = value.toDouble();
    });
    return out;
  }

  static Map<String, List<String>>? _notes(dynamic v) {
    if (v is! Map) return null;
    final out = <String, List<String>>{};
    v.forEach((key, value) {
      if (value is! List) return;
      final list = value
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (list.isNotEmpty) out[key.toString()] = list;
    });
    return out;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
