import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/models/employee.dart';
import 'package:big_boss_bro/state/attendance_controller.dart';
import 'package:big_boss_bro/utils/format.dart';

/// 员工考勤（上班 / 下班打卡）的**纯逻辑**测试：打卡、PIN 校验、员工增删改、
/// 本周分组与工时。
///
/// 盯的是几件最容易出错的事：
/// - 同一天「上班」和「下班」各只能记一次（第二次要把那一次的时间还回来）；
/// - 没签到就点下班要被拦住（不然表里出现「有下班没上班」的怪数据）；
/// - PIN 必须 4 位数字而且**不重复**（重复就分不清谁打的卡）；
/// - 一周必须是**周一到周日**，跨月/跨年也要对；
/// - 删员工不能把历史打卡删掉（上个月的考勤不能凭空变少）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AttendanceController> fresh() async {
    final c = AttendanceController();
    await c.load();
    return c;
  }

  group('上班打卡', () {
    test('PIN 对上 → 打卡成功，记一笔（时间/姓名/类型都对）', () async {
      final c = await fresh();
      expect(await c.addEmployee(name: '张三', pin: '1234'), isNull);

      final res = await c.punch('1234', now: DateTime(2026, 9, 21, 8, 5));

      expect(res.outcome, PunchOutcome.ok);
      expect(res.employee?.name, '张三');
      expect(res.kind, PunchKind.clockIn);
      expect(timeHm(res.at!), '08:05');
      expect(res.worked, isNull, reason: '上班打卡不算工时');
      expect(c.punches.length, 1);
      expect(c.punches.first.kind, PunchKind.clockIn);
    });

    test('同一天再打一次 → alreadyToday，时间还是第一次那次，不重复记账', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 8, 5));

      final again = await c.punch('1234', now: DateTime(2026, 9, 21, 13, 40));

      expect(again.outcome, PunchOutcome.alreadyToday);
      expect(timeHm(again.at!), '08:05', reason: '还回去的是第一次的时间');
      expect(c.punches.length, 1, reason: '只记了一笔');
    });

    test('第二天可以再打一次（按日期分组，不是按 24 小时）', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 23, 50));
      final next = await c.punch('1234', now: DateTime(2026, 9, 22, 0, 10));

      expect(next.outcome, PunchOutcome.ok);
      expect(c.punches.length, 2);
    });

    test('PIN 不对 → wrongPin，什么都不记', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');

      final res = await c.punch('9999');

      expect(res.outcome, PunchOutcome.wrongPin);
      expect(res.employee, isNull);
      expect(c.punches, isEmpty);
    });

    test('没有员工时，任何 PIN 都打不了卡', () async {
      final c = await fresh();
      expect((await c.punch('1234')).outcome, PunchOutcome.wrongPin);
      expect(c.hasEmployees, isFalse);
    });

    test('删掉的员工打不了卡（旧 PIN 立刻失效）', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      final id = c.employees.first.id;

      await c.removeEmployee(id);

      expect((await c.punch('1234')).outcome, PunchOutcome.wrongPin);
    });
  });

  group('下班打卡', () {
    test('签到 → 下班：两次都记上，并算出今天工作了多久', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 8, 5));

      final out = await c.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18, 30));

      expect(out.outcome, PunchOutcome.ok);
      expect(out.kind, PunchKind.clockOut);
      expect(out.worked, const Duration(hours: 10, minutes: 25));
      expect(durationHm(out.worked!), '10:25');
      expect(c.punches.length, 2);
      final id = c.employees.first.id;
      expect(c.clockInAt(id, '2026-09-21'), isNotNull);
      expect(c.clockOutAt(id, '2026-09-21'), isNotNull);
    });

    test('今天还没签到就点下班 → needClockIn，什么都不记', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');

      final res = await c.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18, 30));

      expect(res.outcome, PunchOutcome.needClockIn);
      expect(res.employee?.name, '张三', reason: '认得出人，但要先签到');
      expect(c.punches, isEmpty);
    });

    test('同一天下班打两次 → alreadyToday，不重复记账', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 8));
      await c.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18));

      final again = await c.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 20));

      expect(again.outcome, PunchOutcome.alreadyToday);
      expect(timeHm(again.at!), '18:00', reason: '还回去的是第一次下班的时间');
      expect(c.punches.length, 2, reason: '上班 + 下班各一条');
    });

    test('下班 PIN 不对 → wrongPin', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      final res = await c.punch('0000', kind: PunchKind.clockOut);
      expect(res.outcome, PunchOutcome.wrongPin);
    });

    test('时间段反了（设备时间被改过）→ 工时算 0，不会出现负数', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 18));
      final out = await c.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 8));
      expect(out.worked, Duration.zero);
    });
  });

  group('员工管理', () {
    test('PIN 必须是 4 位数字', () async {
      final c = await fresh();
      expect(await c.addEmployee(name: 'A', pin: '123'), EmployeeError.pinBad);
      expect(await c.addEmployee(name: 'A', pin: '12345'), EmployeeError.pinBad);
      expect(await c.addEmployee(name: 'A', pin: 'abcd'), EmployeeError.pinBad);
      expect(await c.addEmployee(name: 'A', pin: '12 4'), EmployeeError.pinBad);
      expect(await c.addEmployee(name: 'A', pin: '1234'), isNull);
      expect(await c.addEmployee(name: 'B', pin: '0000'), isNull);
    });

    test('PIN 不能重复（不然分不清谁打的卡）', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      expect(await c.addEmployee(name: '李四', pin: '1234'),
          EmployeeError.pinTaken);
      expect(c.employees.length, 1);
    });

    test('姓名不能空', () async {
      final c = await fresh();
      expect(await c.addEmployee(name: '   ', pin: '1234'),
          EmployeeError.nameEmpty);
      expect(c.employees, isEmpty);
    });

    test('改 PIN：新的能用、旧的失效；改成别人用着的会被拒', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      await c.addEmployee(name: '李四', pin: '2222');
      final zhang = c.employees.firstWhere((e) => e.name == '张三');

      expect(await c.setPin(zhang.id, '3333'), isNull);
      expect((await c.punch('3333')).outcome, PunchOutcome.ok,
          reason: '新 PIN 能用');
      expect((await c.punch('1111')).outcome, PunchOutcome.wrongPin,
          reason: '旧 PIN 失效');

      expect(await c.setPin(zhang.id, '2222'), EmployeeError.pinTaken);
      expect(await c.setPin(zhang.id, '22'), EmployeeError.pinBad);
    });

    test('改姓名；找不到的员工返回 notFound', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      final id = c.employees.first.id;

      expect(await c.rename(id, '张三丰'), isNull);
      expect(c.employees.first.name, '张三丰');
      expect(await c.rename(id, '  '), EmployeeError.nameEmpty);
      expect(await c.rename('不存在', 'X'), EmployeeError.notFound);
    });

    test('删员工：名单里没了，但历史打卡记录还留着（只是不显示）', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      final id = c.employees.first.id;
      await c.punch('1111', now: DateTime(2026, 9, 21, 8));

      await c.removeEmployee(id);

      expect(c.employees, isEmpty);
      expect(c.punches.length, 1, reason: '记录还在（上个月的考勤不能凭空变少）');
      expect(c.daySummary('2026-09-21'), isEmpty,
          reason: '员工没了就不在「今天已签到」里显示了');
      expect(c.clockInAt(id, '2026-09-21'), isNotNull,
          reason: '数据还在，以后想补个「已离职员工」视图也能用');
    });
  });

  group('本周考勤', () {
    test('weekOf：给周三 → 周一到周日（跨月、跨年也对）', () {
      // 2026-09-21 是周一，09-23 是周三
      final w = AttendanceController.weekOf(DateTime(2026, 9, 23, 15, 30));
      expect(w.length, 7);
      expect(dayKey(w.first), '2026-09-21');
      expect(dayKey(w.last), '2026-09-27');
      expect(w.first.weekday, DateTime.monday);
      expect(w.last.weekday, DateTime.sunday);

      // 2027-01-01 是周五 → 那一周从 2026-12-28（周一）开始
      final w2 = AttendanceController.weekOf(DateTime(2027, 1, 1));
      expect(dayKey(w2.first), '2026-12-28');
      expect(dayKey(w2.last), '2027-01-03');
    });

    test('格子数据：周一、周三上班+下班 → 时间分开取；出勤和工时都对', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      await c.addEmployee(name: '李四', pin: '2222');
      final zhang = c.employees.firstWhere((e) => e.name == '张三');

      // 周一 8:05-18:30、周三 9:00-17:00
      await c.punch('1111', now: DateTime(2026, 9, 21, 8, 5));
      await c.punch('1111',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18, 30));
      await c.punch('1111', now: DateTime(2026, 9, 23, 9, 0));
      await c.punch('1111',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 23, 17, 0));

      final days = AttendanceController.weekOf(DateTime(2026, 9, 23));

      expect(timeHm(c.clockInAt(zhang.id, '2026-09-21')!), '08:05');
      expect(timeHm(c.clockOutAt(zhang.id, '2026-09-21')!), '18:30');
      expect(c.clockInAt(zhang.id, '2026-09-22'), isNull);
      expect(c.daysPresent(zhang.id, days), 2);
      // 10:25 + 8:00 = 18:25 → 18.4 小时
      expect(durationHm(c.weekWorked(zhang.id, days)), '18:25');
      expect(hoursDecimal(c.weekWorked(zhang.id, days)), '18.4');

      final li = c.employees.firstWhere((e) => e.name == '李四');
      expect(c.daysPresent(li.id, days), 0);
      expect(c.weekWorked(li.id, days), Duration.zero);
    });

    test('只打了上班没打下班：出勤算 1 天，工时不算', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      final id = c.employees.first.id;
      await c.punch('1111', now: DateTime(2026, 9, 21, 8, 5));

      final days = AttendanceController.weekOf(DateTime(2026, 9, 21));
      expect(c.daysPresent(id, days), 1);
      expect(c.weekWorked(id, days), Duration.zero);
      expect(c.workedOn(id, '2026-09-21'), isNull);
    });

    test('「今天已签到」列表：按上班时间排序，带上上班/下班', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1111');
      await c.addEmployee(name: '李四', pin: '2222');
      await c.punch('2222', now: DateTime(2026, 9, 21, 9, 30));
      await c.punch('1111', now: DateTime(2026, 9, 21, 7, 55));
      await c.punch('2222',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18, 0));

      final list = c.daySummary('2026-09-21');

      expect(list.map((r) => r.employee.name), ['张三', '李四'],
          reason: '按上班时间从早到晚');
      expect(timeHm(list.first.clockIn!), '07:55');
      expect(list.first.clockOut, isNull);
      expect(timeHm(list.last.clockOut!), '18:00');
    });
  });

  group('同步用的小接口', () {
    test('打卡会带上「已上传」标记；标记后 unpushedPunches 就空了', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 8));

      expect(c.punches.first.pushed, isFalse);
      expect(c.unpushedPunches.length, 1);

      await c.markPunchesPushed([c.punches.first.id]);

      expect(c.unpushedPunches, isEmpty);
      expect(c.punches.first.pushed, isTrue);
    });

    test('采纳服务器上的打卡：按 id 合并（本地已有的不重复加）', () async {
      final c = await fresh();
      await c.addEmployee(name: '张三', pin: '1234');
      await c.punch('1234', now: DateTime(2026, 9, 21, 8));
      final id = c.employees.first.id;
      final mine = c.punches.first;

      await c.adoptServerPunches([
        // 同一条（服务器那份）
        AttendancePunch(
            id: mine.id,
            employeeId: id,
            at: mine.at,
            kind: PunchKind.clockIn),
        // 服务器上新的（别的设备打的）
        AttendancePunch(
            id: 'p-other',
            employeeId: id,
            at: DateTime(2026, 9, 21, 18),
            kind: PunchKind.clockOut),
      ]);

      expect(c.punches.length, 2, reason: '同一个 id 不会变成两条');
      expect(c.punches.map((p) => p.id), contains('p-other'));
      expect(c.unpushedPunches, isEmpty, reason: '服务器来的都算已上传');
    });

    test('用服务器那份整体替换员工名单（不带同步钩子）', () async {
      final c = await fresh();
      await c.addEmployee(name: '本地的小明', pin: '9999');

      await c.replaceStaffFromServer(const [
        Employee(id: 'e1', name: '服务器上的张三', pin: '1111'),
      ]);

      expect(c.employees.length, 1);
      expect(c.employees.first.name, '服务器上的张三');
      expect(c.staffSnapshot().first.pin, '1111');
    });
  });

  group('持久化', () {
    test('打卡后「重启」（新建 controller + load）→ 员工和记录都还在', () async {
      final a = await fresh();
      await a.addEmployee(name: '张三', pin: '1234');
      await a.punch('1234', now: DateTime(2026, 9, 21, 8, 5));
      await a.punch('1234',
          kind: PunchKind.clockOut, now: DateTime(2026, 9, 21, 18, 30));

      final b = AttendanceController();
      await b.load();

      expect(b.employees.length, 1);
      expect(b.employees.first.name, '张三');
      expect(b.punches.length, 2);
      expect(b.punches.first.kind, PunchKind.clockIn);
      expect(b.punches.last.kind, PunchKind.clockOut, reason: '上班/下班存得住');
      expect(timeHm(b.punches.last.at), '18:30');
      // 重启后当天再打上班 → 还是会说「已经打过」
      expect((await b.punch('1234', now: DateTime(2026, 9, 21, 9))).outcome,
          PunchOutcome.alreadyToday);
    });

    test('坏数据不会崩（存了个乱七八糟的 JSON 也当空的）', () async {
      SharedPreferences.setMockInitialValues({
        'attendance_employees': 'not json at all',
        'attendance_punches': '{"a":1}',
      });
      final c = AttendanceController();
      await c.load();
      expect(c.employees, isEmpty);
      expect(c.punches, isEmpty);
    });
  });
}
