/// 账号与权限。
///
/// 只有两种角色（够用且不容易搞错）：
/// - [AccountRole.admin] 管理员：菜单管理、Excel 导入、设置、日结、删订单、账号管理。
/// - [AccountRole.cashier] 收银员：点单、下单、加单、结账、折扣、看进行中的单。
library;

/// 角色。
enum AccountRole {
  admin('admin'),
  cashier('cashier');

  final String id;
  const AccountRole(this.id);

  static AccountRole fromId(String? id) => AccountRole.values.firstWhere(
        (e) => e.id == id,
        orElse: () => AccountRole.cashier,
      );
}

/// 一个账号。
///
/// 密码（[pin]）是**明文存在本机**的：这类店用小票机不需要（也不该）联网，
/// 明文足够挡住「店员随手改菜单」，不用于防黑客。想更安全可以以后加哈希。
class Account {
  /// 登录名（唯一，例如 `admin` / `maria`）。
  final String id;

  /// 显示名（打在小票「收银员」那一行，可以写中文名）。
  final String name;

  /// 密码（4~8 位数字比较顺手，但不强制）。
  final String pin;

  final AccountRole role;

  const Account({
    required this.id,
    required this.name,
    required this.pin,
    this.role = AccountRole.cashier,
  });

  bool get isAdmin => role == AccountRole.admin;

  Account copyWith({String? name, String? pin, AccountRole? role}) => Account(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
        role: role ?? this.role,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pin': pin,
        'role': role.id,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? json['id'] as String,
        pin: (json['pin'] as String?) ?? '',
        role: AccountRole.fromId(json['role'] as String?),
      );
}

/// 默认管理员账号（首次启动自动创建）。
const String kDefaultAdminId = 'admin';
const String kDefaultAdminPin = '8888';

/// 首次启动的默认账号列表。
List<Account> defaultAccounts() => [
      const Account(
        id: kDefaultAdminId,
        name: 'admin',
        pin: kDefaultAdminPin,
        role: AccountRole.admin,
      ),
    ];
