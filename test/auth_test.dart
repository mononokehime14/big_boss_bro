import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/models/account.dart';
import 'package:big_boss_bro/state/auth_controller.dart';

/// 账号 + 权限（管理员 / 收银员 / 普通店员）。
///
/// 内置两个账号：`admin / 8888`（管理员）和 `user / 1234`（普通店员，**看不到考勤页**）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AuthController> fresh() async {
    final auth = AuthController();
    await auth.load();
    return auth;
  }

  test('首次启动自动创建 admin / 8888 + user / 1234，且还没登录', () async {
    final auth = await fresh();
    expect(auth.accounts.length, 2);
    expect(auth.accounts.first.id, kDefaultAdminId);
    expect(auth.accounts.first.pin, kDefaultAdminPin);
    expect(auth.accounts.first.isAdmin, isTrue);
    expect(auth.hasAccount(kDefaultUserId), isTrue);
    expect(auth.isSignedIn, isFalse);
    expect(auth.canManage, isFalse);
  });

  test('内置 user 账号：密码 1234、就是个普通店员（不能管理，但照样能签到）', () async {
    final auth = await fresh();
    final user = auth.accounts.firstWhere((a) => a.id == kDefaultUserId);
    expect(user.pin, kDefaultUserPin);
    expect(user.isAdmin, isFalse);

    expect(auth.signIn(kDefaultUserId, kDefaultUserPin), isTrue);
    expect(auth.isSignedIn, isTrue);
    // 普通店员：能点单/结账/签到（签到页人人可进），
    // 但"每周考勤 / 员工管理 / 设置"这些要管理员密码（canManage=false）
    expect(auth.canManage, isFalse);
  });

  test('老装机（只有 admin）升级后会补上内置 user；删掉之后不会再回来', () async {
    // 模拟"升级前"的本机数据：只有 admin 一条
    SharedPreferences.setMockInitialValues({
      'accounts': jsonEncode([
        const Account(
          id: kDefaultAdminId,
          name: 'admin',
          pin: kDefaultAdminPin,
          role: AccountRole.admin,
        ).toJson(),
      ]),
    });

    final auth = AuthController();
    await auth.load();
    expect(auth.accounts.length, 2);
    expect(auth.hasAccount(kDefaultUserId), isTrue);

    // 用户不想要它 → 删掉，重新读回来**不会**又冒出来
    auth.signIn(kDefaultAdminId, kDefaultAdminPin);
    expect(await auth.deleteAccount(kDefaultUserId), isTrue);
    final again = AuthController();
    await again.load();
    expect(again.hasAccount(kDefaultUserId), isFalse);
  });

  test('登录：密码不对进不去，对了才进', () async {
    final auth = await fresh();
    expect(auth.signIn('admin', '1234'), isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(auth.signIn('nobody', '8888'), isFalse);

    expect(auth.signIn('admin', '8888'), isTrue);
    expect(auth.isSignedIn, isTrue);
    expect(auth.currentName, 'admin');
    expect(auth.isAdmin, isTrue);
    expect(auth.canManage, isTrue);
  });

  test('收银员不能管理；输管理员密码可以临时提权（本次会话）', () async {
    final auth = await fresh();
    await auth.addAccount(
      id: 'maria',
      name: 'Maria',
      pin: '1111',
      role: AccountRole.cashier,
    );
    expect(auth.signIn('maria', '1111'), isTrue);
    expect(auth.isAdmin, isFalse);
    expect(auth.canManage, isFalse);

    // 错的密码提不了权
    expect(auth.elevate('9999'), isFalse);
    expect(auth.canManage, isFalse);

    // 管理员密码可以
    expect(auth.elevate('8888'), isTrue);
    expect(auth.canManage, isTrue);
    expect(auth.isElevated, isTrue);

    // 退出登录 → 提权失效
    auth.signOut();
    expect(auth.isSignedIn, isFalse);
    expect(auth.canManage, isFalse);
  });

  test('管理员自己不需要提权', () async {
    final auth = await fresh();
    auth.signIn('admin', '8888');
    expect(auth.elevate('随便'), isTrue);
    expect(auth.isElevated, isFalse);
  });

  test('新增账号：重名 / 空密码 / 空登录名 都会失败', () async {
    final auth = await fresh();
    expect(await auth.addAccount(id: 'admin', name: 'x', pin: '2222'), isFalse);
    expect(await auth.addAccount(id: 'caja1', name: 'x', pin: ''), isFalse);
    expect(await auth.addAccount(id: '', name: 'x', pin: '2222'), isFalse);
    expect(await auth.addAccount(id: 'caja1', name: 'Caja 1', pin: '2222'),
        isTrue);
    // 内置 2 个（admin + user）+ 新加的 1 个
    expect(auth.accounts.length, 3);
    expect(auth.hasAccount('caja1'), isTrue);
  });

  test('不能删自己、不能删最后一个管理员、不能把最后一个管理员降级', () async {
    final auth = await fresh();
    auth.signIn('admin', '8888');
    // 删自己 → 不行
    expect(await auth.deleteAccount('admin'), isFalse);
    // 降级最后一个管理员 → 不行
    expect(
      await auth.updateAccount(
        auth.accounts.first.copyWith(role: AccountRole.cashier),
      ),
      isFalse,
    );

    // 加一个收银员，再删掉 → 可以
    await auth.addAccount(id: 'caja1', name: 'Caja', pin: '2222');
    expect(await auth.deleteAccount('caja1'), isTrue);
    expect(auth.accounts.length, 2); // 剩下内置的 admin + user
  });

  test('有第二个管理员时，可以删掉其中一个', () async {
    final auth = await fresh();
    auth.signIn('admin', '8888');
    await auth.addAccount(
      id: 'jefe',
      name: 'Jefe',
      pin: '3333',
      role: AccountRole.admin,
    );
    expect(auth.adminCount, 2);
    expect(await auth.deleteAccount('jefe'), isTrue);
    expect(auth.accounts.length, 2); // 内置的 admin + user
  });

  test('改密码后要用新密码登录', () async {
    final auth = await fresh();
    await auth.addAccount(id: 'caja1', name: 'Caja', pin: '2222');
    final caja = auth.accounts.firstWhere((a) => a.id == 'caja1');
    expect(await auth.updateAccount(caja.copyWith(pin: '4444')), isTrue);
    expect(auth.signIn('caja1', '2222'), isFalse);
    expect(auth.signIn('caja1', '4444'), isTrue);
  });

  test('账号存得住：重新读回来还在', () async {
    final auth = await fresh();
    await auth.addAccount(
      id: 'caja1',
      name: 'Caja 1',
      pin: '2222',
      role: AccountRole.cashier,
    );

    final again = AuthController();
    await again.load();
    expect(again.accounts.length, 3); // 内置 admin + user + 刚加的 caja1
    expect(again.hasAccount('caja1'), isTrue);
    expect(again.accounts.firstWhere((a) => a.id == 'caja1').name, 'Caja 1');
  });

  test('Account JSON 往返', () {
    const a = Account(
      id: 'caja1',
      name: 'Caja 1',
      pin: '2222',
      role: AccountRole.admin,
    );
    final back = Account.fromJson(a.toJson());
    expect(back.id, 'caja1');
    expect(back.name, 'Caja 1');
    expect(back.pin, '2222');
    expect(back.role, AccountRole.admin);
    expect(back.isAdmin, isTrue);
  });
}
