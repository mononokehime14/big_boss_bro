/// **员工考勤（上班/下班打卡）**用的模型。
///
/// ⚠️ 这里的「员工」跟「登录账号」（`models/account.dart`）是**两回事**：
///
/// - **账号**：用来登录 App、决定谁能管菜单/设置（登录名 + 密码 + 角色）；
/// - **员工**（本文件）：只用来**打卡**，一个 4 位 PIN 就够了 ——
///   店里端菜/洗碗的同事不需要（也不该）有 App 账号。
library;

/// 一个员工（打卡用）。
class Employee {
  /// 内部 id（本机生成，界面不显示；用 id 而不是姓名，改名不丢历史打卡）。
  final String id;

  /// 显示名（打卡成功时提示「张三 ✓」）。
  final String name;

  /// 4 位数字 PIN，**全局唯一**（不唯一就分不清是谁打的卡）。
  final String pin;

  const Employee({required this.id, required this.name, required this.pin});

  Employee copyWith({String? name, String? pin}) => Employee(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pin': pin};

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        pin: (json['pin'] ?? '').toString(),
      );
}

/// 打卡类型：上班 / 下班。
///
/// 注意枚举值不能叫 `in`（Dart 的保留字），所以叫 [clockIn] / [clockOut]，
/// 存到本机 / 服务器上的值是 `in` / `out`。
enum PunchKind {
  clockIn('in'),
  clockOut('out');

  final String id;
  const PunchKind(this.id);

  /// 老数据没有这个字段 → 当作「上班」（以前只有签到这一种）。
  static PunchKind fromId(String? id) =>
      id == 'out' ? PunchKind.clockOut : PunchKind.clockIn;
}

/// 一次打卡记录（一天一个人最多「上班一条 + 下班一条」）。
class AttendancePunch {
  /// 全局唯一 id（本机生成：时间戳+计数）。同步到后台时当主键，
  /// 两台设备各打各的卡不会互相覆盖。
  final String id;

  final String employeeId;

  final PunchKind kind;

  /// 打卡时间（本机时间）。
  final DateTime at;

  /// **已经推到后台了吗**（本地字段，跟订单的 `dirty` 一个意思）。
  /// 老数据没有 → false，第一次同步会把它补推上去。
  final bool pushed;

  const AttendancePunch({
    required this.id,
    required this.employeeId,
    required this.at,
    this.kind = PunchKind.clockIn,
    this.pushed = false,
  });

  AttendancePunch copyWith({bool? pushed}) => AttendancePunch(
        id: id,
        employeeId: employeeId,
        kind: kind,
        at: at,
        pushed: pushed ?? this.pushed,
      );

  /// 老记录没有 id 时，用「员工 + 时间」推一个**稳定**的 id
  /// （同样的数据每次读出来都一样，同步按 id 合并才不会重复记账）。
  ///
  /// 本机存储和服务器行两条解析路径都用它，保证算出来的是同一个 id。
  static String fallbackId(String employeeId, DateTime at) =>
      '$employeeId-${at.microsecondsSinceEpoch}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'kind': kind.id,
        'at': at.toIso8601String(),
        'pushed': pushed,
      };

  factory AttendancePunch.fromJson(Map<String, dynamic> json) {
    final employeeId = (json['employeeId'] ?? '').toString();
    final at = DateTime.tryParse((json['at'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    // 老记录没有 id → 推一个稳定 id（见 fallbackId）
    final rawId = (json['id'] ?? '').toString();
    return AttendancePunch(
      id: rawId.isNotEmpty ? rawId : fallbackId(employeeId, at),
      employeeId: employeeId,
      kind: PunchKind.fromId(json['kind'] as String?),
      at: at,
      pushed: (json['pushed'] as bool?) ?? false,
    );
  }
}

/// 打卡的结果。
enum PunchOutcome {
  /// 打卡成功。
  ok,

  /// 没有这个 PIN。
  wrongPin,

  /// 今天这一次（上班 / 下班）**已经打过**了（不重复记）。
  alreadyToday,

  /// 点「下班」但今天还没签到（得先签到再下班）。
  needClockIn,
}

/// 打卡结果（界面用它决定提示什么）。
class PunchResult {
  final PunchOutcome outcome;

  /// 打上卡的那个员工（[PunchOutcome.wrongPin] 时为 null）。
  final Employee? employee;

  /// 这次 / 今天那一次的时间（[PunchOutcome.wrongPin] 时为 null）。
  final DateTime? at;

  /// 这次打的是上班还是下班。
  final PunchKind kind;

  /// 下班时：今天上了多久（上班 → 这次下班）；上班打卡时为 null。
  final Duration? worked;

  const PunchResult(
    this.outcome, {
    this.employee,
    this.at,
    this.kind = PunchKind.clockIn,
    this.worked,
  });

  bool get isOk => outcome == PunchOutcome.ok;
}

/// 管理员工时可能出的错（null = 没问题）。
enum EmployeeError {
  /// 姓名为空。
  nameEmpty,

  /// PIN 不是 4 位数字。
  pinBad,

  /// 这个 PIN 已经有人在用了。
  pinTaken,

  /// 找不到这个员工（可能刚被别的操作删了）。
  notFound,
}
