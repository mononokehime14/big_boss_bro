import 'package:flutter/foundation.dart';

import '../data/account_store.dart';
import '../models/account.dart';

/// 登录状态与账号管理。
///
/// - 启动时 [load] 读回账号；`current == null` 表示**还没登录**，界面显示登录页。
/// - 收银员做管理员的事（菜单/设置/日结/删单）时，可以输**管理员密码**临时提权
///   （[elevate]）——不用退出登录再登一次，收银台前面没人愿意折腾。
/// - 提权只持续到「退出登录」或 App 重启。
class AuthController extends ChangeNotifier {
  final AccountStore _store;

  List<Account> _accounts = [];
  Account? _current;
  bool _elevated = false;
  bool _loaded = false;

  AuthController({AccountStore? store}) : _store = store ?? AccountStore();

  List<Account> get accounts => List.unmodifiable(_accounts);
  Account? get current => _current;
  bool get loaded => _loaded;

  /// 是否已登录。
  bool get isSignedIn => _current != null;

  /// 当前账号本身是管理员。
  bool get isAdmin => _current?.isAdmin ?? false;

  /// 能不能做管理员的事（本人是管理员，或已临时提权）。
  bool get canManage => isAdmin || _elevated;

  /// 临时提权了吗（界面可以提示一下）。
  bool get isElevated => _elevated && !isAdmin;

  String get currentName => _current?.name ?? '';

  Future<void> load() async {
    _accounts = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  /// 登录。成功返回 true；用户名或密码不对返回 false。
  bool signIn(String id, String pin) {
    for (final a in _accounts) {
      if (a.id == id && a.pin == pin) {
        _current = a;
        _elevated = false;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// 退出登录（回到登录页）。
  void signOut() {
    _current = null;
    _elevated = false;
    notifyListeners();
  }

  /// 用**任意一个管理员账号的密码**临时提权。
  bool elevate(String pin) {
    if (isAdmin) return true;
    final p = pin.trim();
    if (p.isEmpty) return false;
    for (final a in _accounts) {
      if (a.isAdmin && a.pin == p) {
        _elevated = true;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// 校验某个账号的密码（修改自己的密码时用）。
  bool checkPin(String accountId, String pin) {
    for (final a in _accounts) {
      if (a.id == accountId) return a.pin == pin;
    }
    return false;
  }

  bool hasAccount(String id) => _accounts.any((a) => a.id == id);

  int get adminCount => _accounts.where((a) => a.isAdmin).length;

  /// 新增账号。id 重复、或信息不全（空 id / 空密码）返回 false。
  Future<bool> addAccount({
    required String id,
    required String name,
    required String pin,
    AccountRole role = AccountRole.cashier,
  }) async {
    final login = id.trim();
    final pass = pin.trim();
    if (login.isEmpty || pass.isEmpty || hasAccount(login)) return false;
    _accounts = [
      ..._accounts,
      Account(
        id: login,
        name: name.trim().isEmpty ? login : name.trim(),
        pin: pass,
        role: role,
      ),
    ];
    await _persist();
    return true;
  }

  /// 改显示名 / 密码 / 角色。
  Future<bool> updateAccount(Account account) async {
    final i = _accounts.indexWhere((a) => a.id == account.id);
    if (i < 0) return false;
    // 不能把最后一个管理员降级成收银员，否则没人能管菜单了
    if (_accounts[i].isAdmin && !account.isAdmin && adminCount <= 1) {
      return false;
    }
    _accounts = List.of(_accounts)..[i] = account;
    if (_current?.id == account.id) _current = account;
    await _persist();
    return true;
  }

  /// 删除账号。不能删自己、也不能删掉最后一个管理员。
  Future<bool> deleteAccount(String id) async {
    Account? target;
    for (final a in _accounts) {
      if (a.id == id) target = a;
    }
    if (target == null) return false;
    if (_current?.id == id) return false;
    if (target.isAdmin && adminCount <= 1) return false;
    _accounts = _accounts.where((a) => a.id != id).toList();
    await _persist();
    return true;
  }

  Future<void> _persist() async {
    await _store.save(_accounts);
    notifyListeners();
  }
}
