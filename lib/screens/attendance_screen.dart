import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/employee.dart';
import '../state/attendance_controller.dart';
import '../utils/format.dart';
import '../widgets/admin_gate.dart';
import '../widgets/clock_in_dialog.dart';

/// **员工考勤页**（独立一页，不在点单/订单里面）。
///
/// 两半：
/// 1. **员工**：两个大按钮 —— 绿色「签 到」/ 蓝色「下 班」→ 输 4 位 PIN → 打卡成功；
///    下面列出「今天已签到」（上班 → 下班时间），员工自己能看到确实打上了。
/// 2. **管理员**（要点一下 + 输管理员密码，默认 8888）：看**本周**考勤表
///    （员工 × 周一到周日，格子里是上班 / 下班时间 + 本周工时）、
///    加 / 删员工、改每个人的 PIN。
///
/// 数据会同步到后台（Supabase 的 `attendance_staff` / `attendance_punches` 两张表），
/// 多台设备共用一个考勤表；断网也照常打卡，联网后自动补推。
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  /// 管理员区解锁了吗（进页面默认锁着，避免收银员随手改 PIN）。
  bool _adminOpen = false;

  /// 当前显示的那一周（用这一周里的任意一天表示）。
  DateTime _weekAnchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<AttendanceController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('attendance.title')),
        actions: [
          if (_adminOpen)
            TextButton.icon(
              onPressed: () => setState(() => _adminOpen = false),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: Text(L10n.t('attendance.lock')),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _clockCard(ctl),
          const SizedBox(height: 14),
          _todayCard(ctl),
          const SizedBox(height: 14),
          if (!_adminOpen)
            _adminLockedCard()
          else ...[
            _weekCard(ctl),
            const SizedBox(height: 14),
            _staffCard(ctl),
          ],
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- 员工这一半 ----------------

  /// 两个大按钮：上班（绿，最大）+ 下班（蓝）——故意做得又高又显眼。
  Widget _clockCard(AttendanceController ctl) {
    final now = DateTime.now();
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          children: [
            Text(
              '${dayKey(now)}  ${L10n.t(_weekdayKey(now))}',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 150,
              child: FilledButton.icon(
                key: const Key('clockin-button'),
                onPressed: () => _punch(ctl, PunchKind.clockIn),
                icon: const Icon(Icons.how_to_reg, size: 46),
                label: Text(
                  L10n.t('attendance.clockIn'),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA85A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 104,
              child: FilledButton.icon(
                key: const Key('clockout-button'),
                onPressed: () => _punch(ctl, PunchKind.clockOut),
                icon: const Icon(Icons.logout, size: 34),
                label: Text(
                  L10n.t('attendance.clockOut'),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打卡（上班 / 下班都走这里）。
  ///
  /// 结果（谁、几点、今天工作了多久）在对话框里给员工看清楚，这里不用再提示。
  Future<void> _punch(AttendanceController ctl, PunchKind kind) async {
    if (!ctl.hasEmployees) {
      _toast(L10n.t('attendance.noEmployees'));
      return;
    }
    await showClockInDialog(
      context,
      kind: kind,
      onSubmit: (pin) => ctl.punch(pin, kind: kind),
    );
  }

  /// 「今天已签到」列表：每人一行，右边显示「上班 → 下班」时间。
  Widget _todayCard(AttendanceController ctl) {
    final list = ctl.daySummary(dayKey(DateTime.now()));
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined,
                    size: 18, color: Color(0xFF1FA85A)),
                const SizedBox(width: 6),
                Text(
                  '${L10n.t('attendance.todayList')} (${list.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.t('attendance.todayNone'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              )
            else
              for (final r in list)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        const Color(0xFF1FA85A).withValues(alpha: .12),
                    child: Text(
                      _firstChar(r.employee.name),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1FA85A)),
                    ),
                  ),
                  title: Text(r.employee.name),
                  // 上班 → 下班（只打了上班就只显示上班）
                  trailing: Text(
                    r.clockOut == null
                        ? '${timeHm(r.clockIn!)} →'
                        : '${timeHm(r.clockIn!)} → ${timeHm(r.clockOut!)}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ---------------- 管理员这一半 ----------------

  Widget _adminLockedCard() => Card(
        color: Colors.white,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.lock_outline, color: Color(0xFF1FA85A)),
          title: Text(L10n.t('attendance.adminOpen')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openAdmin,
        ),
      );

  Future<void> _openAdmin() async {
    // 已经是管理员（或本次会话提权过）→ 直接开；否则弹密码框
    final ok = await requireAdmin(
      context,
      reason: L10n.t('attendance.adminHint'),
    );
    if (!ok || !mounted) return;
    setState(() => _adminOpen = true);
  }

  /// 本周考勤表：一行一个员工，7 列是周一到周日（格子里是签到时间）。
  Widget _weekCard(AttendanceController ctl) {
    final days = AttendanceController.weekOf(_weekAnchor);
    final labels = _weekdayLabels();

    Widget cell(String text,
            {double width = 62,
            bool header = false,
            bool bold = false,
            Color? color,
            Alignment align = Alignment.center}) =>
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Align(
              alignment: align,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: header ? 12 : 14,
                  fontWeight: (header || bold) ? FontWeight.w700 : null,
                  color: header ? Colors.grey.shade700 : color,
                ),
              ),
            ),
          ),
        );

    // 某员工某天的格子：上面绿色是上班、下面蓝色是下班；都没打就一个「—」
    Widget dayCell(Employee e, DateTime d) {
      final day = dayKey(d);
      final i = ctl.clockInAt(e.id, day);
      final o = ctl.clockOutAt(e.id, day);
      if (i == null && o == null) {
        return cell('—', color: Colors.grey.shade400);
      }
      return SizedBox(
        width: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                i == null ? '—' : timeHm(i),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: i == null
                        ? Colors.grey.shade400
                        : const Color(0xFF1FA85A)),
              ),
              Text(
                o == null ? '—' : timeHm(o),
                style: TextStyle(
                    fontSize: 13,
                    color: o == null
                        ? Colors.grey.shade400
                        : const Color(0xFF1565C0)),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  L10n.t('attendance.week'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_md(days.first)} ~ ${_md(days.last)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  // 用「日期 - 7 天」重新构造（别用 Duration：夏令时那天会偏一小时）
                  onPressed: () => setState(() => _weekAnchor = DateTime(
                      _weekAnchor.year, _weekAnchor.month, _weekAnchor.day - 7)),
                ),
                TextButton(
                  onPressed: () => setState(() => _weekAnchor = DateTime.now()),
                  child: Text(L10n.t('attendance.today')),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _weekAnchor = DateTime(
                      _weekAnchor.year, _weekAnchor.month, _weekAnchor.day + 7)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 表头
                  Row(
                    children: [
                      cell(L10n.t('attendance.employee'),
                          width: 110, header: true, align: Alignment.centerLeft),
                      for (var i = 0; i < 7; i++)
                        cell('${labels[i]}\n${_md(days[i])}',
                            width: 64, header: true),
                      cell(L10n.t('attendance.days'), width: 56, header: true),
                      cell(L10n.t('attendance.hours'), width: 64, header: true),
                    ],
                  ),
                  const Divider(height: 1),
                  if (ctl.employees.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        L10n.t('attendance.noEmployees'),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    )
                  else
                    for (final e in ctl.employees)
                      Row(
                        children: [
                          cell(e.name,
                              width: 110,
                              bold: true,
                              align: Alignment.centerLeft),
                          for (final d in days) dayCell(e, d),
                          cell('${ctl.daysPresent(e.id, days)}',
                              width: 56, bold: true),
                          cell(hoursDecimal(ctl.weekWorked(e.id, days)),
                              width: 64, bold: true),
                        ],
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 图例：格子里上下两行分别是上班 / 下班
            Row(
              children: [
                _legendDot(const Color(0xFF1FA85A), L10n.t('attendance.legendIn')),
                const SizedBox(width: 14),
                _legendDot(const Color(0xFF1565C0), L10n.t('attendance.legendOut')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 图例上的小圆点 + 文字。
  Widget _legendDot(Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      );

  /// 员工管理：加 / 改（姓名 + PIN）/ 删。
  Widget _staffCard(AttendanceController ctl) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  L10n.t('attendance.manage'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _editEmployee(ctl, null),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(L10n.t('attendance.add')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (ctl.employees.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.t('attendance.noEmployees'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              )
            else
              for (final e in ctl.employees)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.name),
                  // PIN 只在管理员区显示（老板要告诉员工自己的 PIN）
                  subtitle: Text(
                    '${L10n.t('attendance.pinShort')}: ${e.pin}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: L10n.t('attendance.edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editEmployee(ctl, e),
                      ),
                      IconButton(
                        tooltip: L10n.t('common.delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteEmployee(ctl, e),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// 加员工 / 改员工的弹窗（姓名 + PIN，两个都能改）。
  Future<void> _editEmployee(AttendanceController ctl, Employee? existing) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final pinCtl = TextEditingController(text: existing?.pin ?? '');
    String? error;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(existing == null
              ? L10n.t('attendance.add')
              : L10n.t('attendance.edit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: L10n.t('attendance.name'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinCtl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: L10n.t('attendance.pin'),
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(L10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final err = existing == null
                    ? await ctl.addEmployee(
                        name: nameCtl.text, pin: pinCtl.text)
                    : await _applyEdit(ctl, existing, nameCtl.text, pinCtl.text);
                if (err == null) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                  return;
                }
                setState(() => error = _errorText(err));
              },
              child: Text(L10n.t('common.ok')),
            ),
          ],
        ),
      ),
    );

    nameCtl.dispose();
    pinCtl.dispose();
    if (save == true && mounted) _toast(L10n.t('attendance.saved'));
  }

  /// 改姓名 + 改 PIN（哪个先失败就报哪个）。
  Future<EmployeeError?> _applyEdit(
    AttendanceController ctl,
    Employee existing,
    String name,
    String pin,
  ) async {
    if (name.trim() != existing.name) {
      final err = await ctl.rename(existing.id, name);
      if (err != null) return err;
    }
    if (pin.trim() != existing.pin) {
      return ctl.setPin(existing.id, pin);
    }
    return null;
  }

  Future<void> _deleteEmployee(AttendanceController ctl, Employee e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(e.name),
        content: Text(L10n.t('attendance.deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ctl.removeEmployee(e.id);
    if (mounted) _toast(L10n.t('attendance.saved'));
  }

  static String _errorText(EmployeeError e) => switch (e) {
        EmployeeError.nameEmpty => L10n.t('attendance.errName'),
        EmployeeError.pinBad => L10n.t('attendance.errPin'),
        EmployeeError.pinTaken => L10n.t('attendance.errPinTaken'),
        EmployeeError.notFound => L10n.t('attendance.errNotFound'),
      };

  /// 名字的第一个字（头像里显示）。
  static String _firstChar(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  /// 周一到周日的短名（自己写死在文案里，不依赖系统本地化的顺序）。
  static List<String> _weekdayLabels() => [
        L10n.t('attendance.mon'),
        L10n.t('attendance.tue'),
        L10n.t('attendance.wed'),
        L10n.t('attendance.thu'),
        L10n.t('attendance.fri'),
        L10n.t('attendance.sat'),
        L10n.t('attendance.sun'),
      ];

  static String _weekdayKey(DateTime d) => switch (d.weekday) {
        DateTime.monday => 'attendance.mon',
        DateTime.tuesday => 'attendance.tue',
        DateTime.wednesday => 'attendance.wed',
        DateTime.thursday => 'attendance.thu',
        DateTime.friday => 'attendance.fri',
        DateTime.saturday => 'attendance.sat',
        _ => 'attendance.sun',
      };

  /// `11-25` 这种短日期（表格里用）。
  static String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
