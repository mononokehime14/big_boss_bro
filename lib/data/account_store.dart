import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// 账号的本地存储（shared_preferences + JSON，和订单/菜单一样的做法）。
///
/// 读的时候如果一条都没有，就**自动创建默认管理员** `admin / 8888`，
/// 保证任何情况下都进得去（不会把自己锁在门外）。
class AccountStore {
  static const _kAccounts = 'accounts';

  Future<List<Account>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccounts);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded
              .whereType<Map>()
              .map((e) => Account.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {
        // 数据坏了就当没有，下面给默认管理员
      }
    }
    final seed = defaultAccounts();
    await save(seed);
    return seed;
  }

  Future<void> save(List<Account> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccounts,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }
}
