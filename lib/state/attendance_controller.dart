import 'package:flutter/foundation.dart';

import '../data/employee_store.dart';
import '../models/employee.dart';
import '../utils/format.dart';

/// **员工考勤**的状态：员工名单 + 打卡记录（上班/下班）+ 本周考勤要用的统计。
///
/// 为什么单独一个 controller（不塞进 PosController）：
/// 这块跟点单/结账完全无关，出问题也不该影响收银；而且它自己一套存储、
/// 一套校验（PIN 唯一、4 位数字），独立开最好测。
///
/// **同步**：数据会跟 Supabase 对（员工名单像菜单那样按版本号走；打卡记录像订单那样
/// 一条一行、按 id 合并）。所有网络搬运都在 `SyncService` 里，这里只负责
/// 「给快照 / 采纳服务器那份 / 标已上传」——跟 `PosController` 的分工一模一样。
class AttendanceController extends ChangeNotifier {
  final EmployeeStore _store;

  List<Employee> _employees = [];
  List<AttendancePunch> _punches = [];
  bool _loaded = false;

  AttendanceController({EmployeeStore? store})
      : _store = store ?? EmployeeStore();

  List<Employee> get employees => List.unmodifiable(_employees);

  /// 打卡记录（按时间先后）。
  List<AttendancePunch> get punches => List.unmodifiable(_punches);

  bool get loaded => _loaded;

  bool get hasEmployees => _employees.isNotEmpty;

  // ---------------- 同步接线（跟 PosController 那套一个意思）----------------

  /// 员工名单变了（加/删/改名/改 PIN）→ SyncService 会推一次。
  void Function()? onStaffChanged;

  /// 有新打卡 → SyncService 会（防抖）推一次，老板那边很快就能看到。
  void Function()? onPunchesChanged;

  /// 同步用：员工名单快照。
  List<Employee> staffSnapshot() => List.of(_employees);

  /// 同步用：本地还没推上去的打卡。
  List<AttendancePunch> get unpushedPunches =>
      _punches.where((p) => !p.pushed).toList();

  /// 同步用：用服务器那份**整体替换**员工名单（服务器版本号更高时）。
  Future<void> replaceStaffFromServer(List<Employee> staff) async {
    _employees = List.of(staff);
    await _persistEmployees(notifySync: false);
  }

  /// 同步用：采纳服务器上的打卡（按 id 合并，服务器那份优先，并标记为已上传）。
  ///
  /// 打卡是**只增不改**的，所以合并就是简单的并集 —— 不会像订单那样有冲突。
  Future<void> adoptServerPunches(List<AttendancePunch> incoming) async {
    if (incoming.isEmpty) return;
    final byId = {for (final p in _punches) p.id: p};
    var changed = false;
    for (final p in incoming) {
      final mine = byId[p.id];
      // 本地已经有了、而且已经推上去过 → 跳过
      if (mine != null && mine.pushed) continue;
      byId[p.id] = p.copyWith(pushed: true);
      changed = true;
    }
    if (!changed) return;
    _punches = byId.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    await _persistPunches(notifySync: false);
  }

  /// 同步用：这些打卡已经推上去了（清掉「待上传」标记）。
  Future<void> markPunchesPushed(List<String> ids) async {
    if (ids.isEmpty) return;
    final set = ids.toSet();
    _punches = [
      for (final p in _punches)
        set.contains(p.id) ? p.copyWith(pushed: true) : p,
    ];
    await _persistPunches(notifySync: false);
  }

  /// 同步用：把所有打卡重新标成「要推」（「重置同步状态」时用）。
  ///
  /// 推上去是 upsert（按 id），所以重复推不会记成两条。
  Future<void> markAllPunchesUnpushed() async {
    if (_punches.isEmpty) return;
    _punches = [for (final p in _punches) p.copyWith(pushed: false)];
    await _persistPunches(notifySync: false);
  }

  Future<void> load() async {
    _employees = await _store.loadEmployees();
    _punches = await _store.loadPunches();
    _loaded = true;
    notifyListeners();
  }

  // ---------------- 打卡 ----------------

  /// 打卡：拿一个 PIN 去认人。
  ///
  /// - 认不出 → [PunchOutcome.wrongPin]（不记任何东西）；
  /// - **上班**：今天已经打过 → [PunchOutcome.alreadyToday]（把第一次的时间还回去）；
  /// - **下班**：今天还没签到 → [PunchOutcome.needClockIn]（要先签到才能下班）；
  ///   今天已经打过下班 → [PunchOutcome.alreadyToday]；正常 → 记一笔并算
  ///   [PunchResult.worked]（今天上了多久）。
  ///
  /// [now] 只是为了测试能固定时间，平时不用传。
  Future<PunchResult> punch(
    String pin, {
    PunchKind kind = PunchKind.clockIn,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final p = pin.trim();
    Employee? who;
    for (final e in _employees) {
      if (e.pin == p) who = e;
    }
    if (who == null) return const PunchResult(PunchOutcome.wrongPin);

    final day = dayKey(at);
    final inAt = clockInAt(who.id, day);

    if (kind == PunchKind.clockIn) {
      if (inAt != null) {
        return PunchResult(PunchOutcome.alreadyToday,
            employee: who, at: inAt, kind: kind);
      }
    } else {
      if (inAt == null) {
        return PunchResult(PunchOutcome.needClockIn, employee: who, kind: kind);
      }
      final outAt = clockOutAt(who.id, day);
      if (outAt != null) {
        return PunchResult(PunchOutcome.alreadyToday,
            employee: who, at: outAt, kind: kind);
      }
    }

    // 记一笔（打卡只增不改、id 全局唯一，同步时不会打架）
    _punches = [
      ..._punches,
      AttendancePunch(
        id: nextPunchId(),
        employeeId: who.id,
        at: at,
        kind: kind,
      ),
    ];
    await _persistPunches();
    return PunchResult(
      PunchOutcome.ok,
      employee: who,
      at: at,
      kind: kind,
      worked: kind == PunchKind.clockOut ? _worked(inAt!, at) : null,
    );
  }

  /// 某员工**某一天**的上班时间（当天最早的一条；没有 → null）。
  DateTime? clockInAt(String employeeId, String day) =>
      _punchTime(employeeId, day, PunchKind.clockIn, earliest: true);

  /// 某员工**某一天**的下班时间（当天最晚的一条；没有 → null）。
  ///
  /// 用「最晚」：正常一天只有一条下班，万一两台设备各打了一次，
  /// 取晚的那个更贴近实际。
  DateTime? clockOutAt(String employeeId, String day) =>
      _punchTime(employeeId, day, PunchKind.clockOut, earliest: false);

  /// 某员工某天上了多久（上班 + 下班都齐了才有值）。
  Duration? workedOn(String employeeId, String day) {
    final i = clockInAt(employeeId, day);
    final o = clockOutAt(employeeId, day);
    if (i == null || o == null) return null;
    return _worked(i, o);
  }

  /// 这一周里，某员工总共上了多久（只算上班+下班都齐的那些天）。
  Duration weekWorked(String employeeId, List<DateTime> days) {
    var total = Duration.zero;
    for (final d in days) {
      final w = workedOn(employeeId, dayKey(d));
      if (w != null) total += w;
    }
    return total;
  }

  /// 某一天的打卡情况（每个员工一行，**只列当天有打卡的**），按上班时间排序。
  List<({Employee employee, DateTime? clockIn, DateTime? clockOut})> daySummary(
    String day,
  ) {
    final out = <({Employee employee, DateTime? clockIn, DateTime? clockOut})>[];
    for (final e in _employees) {
      final i = clockInAt(e.id, day);
      final o = clockOutAt(e.id, day);
      if (i == null && o == null) continue;
      out.add((employee: e, clockIn: i, clockOut: o));
    }
    out.sort((a, b) {
      final ai = a.clockIn, bi = b.clockIn;
      if (ai == null && bi == null) {
        return a.employee.name.compareTo(b.employee.name);
      }
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });
    return out;
  }

  /// 这一周里，某员工来了几天（有上班打卡就算）。
  int daysPresent(String employeeId, List<DateTime> days) =>
      days.where((d) => clockInAt(employeeId, dayKey(d)) != null).length;

  // ---------------- 一周的日期 ----------------

  /// 包含 [anyDay] 的那一周，**周一到周日**共 7 天（日期部分，时间为 0 点）。
  ///
  /// ⚠️ 用 `DateTime(y, m, d ± n)` 重新构造日期，**不要**用 `add(Duration(days: n))`：
  /// 夏令时切换那天加 24 小时会得到前一天 23:00（或后一天 01:00），
  /// 再按日期分组就会把打卡记到隔壁那一天去。
  static List<DateTime> weekOf(DateTime anyDay) {
    final back = anyDay.weekday - DateTime.monday; // 周一 = 0
    final monday = DateTime(anyDay.year, anyDay.month, anyDay.day - back);
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  // ---------------- 员工管理 ----------------

  /// 加一个员工。[pin] 必须是 4 位数字而且要没被占用。
  Future<EmployeeError?> addEmployee({
    required String name,
    required String pin,
  }) async {
    final n = name.trim();
    final p = pin.trim();
    if (n.isEmpty) return EmployeeError.nameEmpty;
    if (!isValidPin(p)) return EmployeeError.pinBad;
    if (pinTaken(p)) return EmployeeError.pinTaken;

    _employees = [
      ..._employees,
      Employee(id: nextStaffId(), name: n, pin: p),
    ];
    await _persistEmployees();
    return null;
  }

  /// 改姓名。
  Future<EmployeeError?> rename(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return EmployeeError.nameEmpty;
    final i = _employees.indexWhere((e) => e.id == id);
    if (i < 0) return EmployeeError.notFound;
    _employees = List.of(_employees)..[i] = _employees[i].copyWith(name: n);
    await _persistEmployees();
    return null;
  }

  /// 改 PIN（同样要 4 位数字、要唯一）。
  Future<EmployeeError?> setPin(String id, String pin) async {
    final p = pin.trim();
    if (!isValidPin(p)) return EmployeeError.pinBad;
    if (pinTaken(p, exceptId: id)) return EmployeeError.pinTaken;
    final i = _employees.indexWhere((e) => e.id == id);
    if (i < 0) return EmployeeError.notFound;
    _employees = List.of(_employees)..[i] = _employees[i].copyWith(pin: p);
    await _persistEmployees();
    return null;
  }

  /// 删员工。**已经打过的卡保留**（不然上个月的考勤会凭空变少），
  /// 只是名单里不再出现他，所以考勤表里也就不显示他了。
  Future<bool> removeEmployee(String id) async {
    final before = _employees.length;
    _employees = _employees.where((e) => e.id != id).toList();
    if (_employees.length == before) return false;
    await _persistEmployees();
    return true;
  }

  /// PIN 是不是 4 位数字。
  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin.trim());

  /// 这个 PIN 有没有被别的员工用着（[exceptId] = 改自己的 PIN 时排除自己）。
  bool pinTaken(String pin, {String? exceptId}) {
    final p = pin.trim();
    if (p.isEmpty) return false;
    return _employees.any((e) => e.pin == p && e.id != exceptId);
  }

  // ---------------- id 生成 ----------------

  int _counter = 0;

  /// 员工 id：时间戳 + 递增，保证不撞（跟订单号一个思路）。
  String nextStaffId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  /// 打卡 id（后台那张表的主键，加个 `p` 前缀一眼看出是打卡）。
  String nextPunchId() => 'p${nextStaffId()}';

  // ---------------- 内部 ----------------

  /// 某员工某天某一类打卡的时间（[earliest] = 取最早 / 最晚一条）。
  DateTime? _punchTime(
    String employeeId,
    String day,
    PunchKind kind, {
    required bool earliest,
  }) {
    DateTime? best;
    for (final p in _punches) {
      if (p.employeeId != employeeId) continue;
      if (p.kind != kind) continue;
      if (dayKey(p.at) != day) continue;
      if (best == null) {
        best = p.at;
        continue;
      }
      if (earliest ? p.at.isBefore(best) : p.at.isAfter(best)) best = p.at;
    }
    return best;
  }

  /// 上班到下班之间的时长（万一时间段是反的 —— 比如设备时间被改过 —— 返回 0）。
  static Duration _worked(DateTime from, DateTime to) {
    final d = to.difference(from);
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> _persistEmployees({bool notifySync = true}) async {
    await _store.saveEmployees(_employees);
    // 「服务器写本地」的时候不通知同步（不然会多跑一趟）
    if (notifySync) onStaffChanged?.call();
    notifyListeners();
  }

  Future<void> _persistPunches({bool notifySync = true}) async {
    await _store.savePunches(_punches);
    if (notifySync) onPunchesChanged?.call();
    notifyListeners();
  }
}
