import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 「本地已经删掉、但**还没告诉后台**」的单号。
///
/// 为什么要专门存下来：删单的时候如果正好断网，App 重启后还得记得去后台把那一行也删掉 ——
/// 否则下一次同步会把这张单**又拉回来**（看起来就像「删不掉」）。
class DeletedOrdersStore {
  static const _key = 'orders_deleted_ids';

  /// 只留最近这么多条（够用了，防止无限增长；真丢的也是很久以前的）。
  static const int keep = 500;

  Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        ids.length > keep ? ids.sublist(ids.length - keep) : List.of(ids);
    await prefs.setString(_key, jsonEncode(trimmed));
  }
}
