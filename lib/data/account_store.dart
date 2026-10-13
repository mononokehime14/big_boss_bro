import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// 账号的本地存储（shared_preferences + JSON，和订单/菜单一样的做法）。
///
/// 读的时候如果一条都没有，就**自动创建默认账号**：
/// `admin / 8888`（管理员）和 `user / 1234`（普通店员，权限和收银员一样），
/// 保证任何情况下都进得去（不会把自己锁在门外）。
///
/// 老装机（升级前只有 admin）也会**补一次** `user` —— 靠 [_kSeededUser] 这个标记，
/// 所以补过之后你再把它删掉，就不会又冒出来。
class AccountStore {
  static const _kAccounts = 'accounts';

  /// 「内置 user 账号已经补过了」的标记（只补一次）。
  static const _kSeededUser = 'seeded_default_user_v1';

  Future<List<Account>> load() async {
    final prefs = await SharedPreferences.getInstance();
    List<Account>? parsed;

    final raw = prefs.getString(_kAccounts);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded
              .whereType<Map>()
              .map((e) => Account.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (list.isNotEmpty) parsed = list;
        }
      } catch (_) {
        // 数据坏了就当没有，下面给默认账号
      }
    }

    // 一条都没有（第一次装 / 数据坏了）→ 默认两个账号
    var accounts = parsed ?? defaultAccounts();

    // 迁移：老数据只有 admin → 补上内置的 user（**只补一次**）
    if (!(prefs.getBool(_kSeededUser) ?? false)) {
      if (!accounts.any((a) => a.id == kDefaultUserId)) {
        accounts = [...accounts, kDefaultUserAccount];
      }
      await prefs.setBool(_kSeededUser, true);
      await save(accounts);
    }

    return accounts;
  }

  Future<void> save(List<Account> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccounts,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }
}
