import '../models/employee.dart';

/// 员工名单在服务器上的一行（表 `attendance_staff`，永远只有一行 `id = 'current'`）。
///
/// 跟菜单一样的思路：整份名单存成一个 JSON + 一个版本号，
/// 设备之间靠版本号决定「要不要拉服务器那份」。
class RemoteStaff {
  final int version;
  final DateTime updatedAt;
  final String deviceId;
  final List<Employee> staff;

  const RemoteStaff({
    required this.version,
    required this.updatedAt,
    required this.staff,
    this.deviceId = '',
  });

  factory RemoteStaff.fromRow(Map<String, dynamic> row) => RemoteStaff(
        version: (row['version'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        deviceId: (row['device_id'] ?? '').toString(),
        staff: AttendanceSync.staffFromData(row['data']),
      );
}

/// **考勤同步的纯逻辑**（不碰网络、不碰界面 → 好写单测）。
///
/// 两条线各自同步，规则都很简单：
/// - **员工名单**：跟菜单一样「版本号大的赢」；本地改过（`staffDirty`）就先推本地；
/// - **打卡记录**：只增不改，所以就是**并集**（按 id 合并）—— 两台设备各打各的卡
///   不会互相覆盖，也不需要什么冲突规则。
class AttendanceSync {
  const AttendanceSync._();

  /// 员工名单 → 要写进服务器那一行的字段。
  static Map<String, dynamic> staffToRow(
    List<Employee> staff, {
    required String deviceId,
  }) =>
      {
        'id': 'current',
        'device_id': deviceId,
        'data': {
          'staff': staff.map((e) => e.toJson()).toList(),
        },
      };

  /// 服务器那一行的 `data` → 员工名单。
  ///
  /// 数据坏了（不是对象 / 里面不是数组）就返回空名单 —— 「空」比「崩」好。
  static List<Employee> staffFromData(dynamic data) {
    if (data is! Map) return const [];
    final raw = data['staff'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Employee.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty && e.pin.isNotEmpty)
        .toList();
  }

  /// 员工名单要不要**用服务器那份覆盖本地**？
  ///
  /// 本地有没推上去的改动（[localDirty]）→ 不覆盖（先把本地的推上去，后改的赢）；
  /// 否则服务器版本更高 → 覆盖。
  static bool shouldPullStaff({
    required int serverVersion,
    required int localVersion,
    required bool localDirty,
  }) =>
      !localDirty && serverVersion > localVersion;

  /// 一次打卡 → 服务器 `attendance_punches` 的一行。
  ///
  /// 注意**不送** `created_at`（那是服务器收到的时间，由数据库自己写）：
  /// 增量拉取就是按它走的，让客户端去写会乱。
  static Map<String, dynamic> punchToRow(
    AttendancePunch p, {
    required String deviceId,
  }) =>
      {
        'id': p.id,
        'employee_id': p.employeeId,
        'kind': p.kind.id,
        'at': p.at.toIso8601String(),
        'device_id': deviceId,
      };

  /// 服务器一行 → 一次打卡（从服务器来的都算「已上传」）。
  ///
  /// 万一那一行没有 `id`（正常不会有：它是主键），就用「员工 + 时间」推一个
  /// **稳定** id —— 跟本机那条解析路径用同一个 [AttendancePunch.fallbackId]，
  /// 不然两边算出来的 id 不一样，同步会当成两条新记录重复加。
  static AttendancePunch punchFromRow(Map<String, dynamic> row) {
    final employeeId = (row['employee_id'] ?? '').toString();
    final at = DateTime.tryParse((row['at'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rawId = (row['id'] ?? '').toString();
    return AttendancePunch(
      id: rawId.isNotEmpty ? rawId : AttendancePunch.fallbackId(employeeId, at),
      employeeId: employeeId,
      kind: PunchKind.fromId(row['kind'] as String?),
      at: at,
      pushed: true,
    );
  }

  /// 服务器收到这一行的时间（增量拉取的水位线用它，**不是**设备上的打卡时间）。
  static DateTime punchCreatedAt(Map<String, dynamic> row) =>
      DateTime.tryParse((row['created_at'] ?? '').toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
