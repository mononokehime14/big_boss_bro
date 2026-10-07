import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/employee.dart';
import 'package:big_boss_bro/services/attendance_sync.dart';

/// **考勤同步的纯逻辑**（不联网）：服务器行 ↔ 本地对象、合并规则。
///
/// 盯的是：
/// - 员工名单 JSON 往返不丢字段；坏数据当空名单（不能崩）；
/// - 打卡行里**不能带** `created_at`（那是服务器写的，增量水位线靠它）；
/// - 老数据没有 `kind` → 当「上班」；
/// - 「要不要拉服务器那份名单」的三种情况。
void main() {
  const staff = [
    Employee(id: 'e1', name: '张三', pin: '1111'),
    Employee(id: 'e2', name: '李四', pin: '2222'),
  ];

  group('员工名单', () {
    test('往返：staffToRow → staffFromData 一个字段都不丢', () {
      final row = AttendanceSync.staffToRow(staff, deviceId: '收银台A');
      expect(row['id'], 'current');
      expect(row['device_id'], '收银台A');

      final back = AttendanceSync.staffFromData(row['data']);
      expect(back.length, 2);
      expect(back.first.id, 'e1');
      expect(back.first.name, '张三');
      expect(back.first.pin, '1111');
      expect(back.last.name, '李四');
    });

    test('坏数据 → 空名单（不抛异常）', () {
      expect(AttendanceSync.staffFromData(null), isEmpty);
      expect(AttendanceSync.staffFromData('不是对象'), isEmpty);
      expect(AttendanceSync.staffFromData(<String, dynamic>{}), isEmpty);
      expect(
        AttendanceSync.staffFromData({'staff': '不是数组'}),
        isEmpty,
      );
      // 少了必要字段的行会被丢掉（id / pin 必须有）
      final rows = AttendanceSync.staffFromData({
        'staff': [
          {'name': '没有 id 和 pin'},
          {'id': 'e9', 'name': '王五', 'pin': '9999'},
        ],
      });
      expect(rows.length, 1);
      expect(rows.first.id, 'e9');
    });

    test('RemoteStaff.fromRow：版本号/时间/名单都读得出来', () {
      final remote = RemoteStaff.fromRow({
        'id': 'current',
        'version': 7,
        'updated_at': '2026-09-20T12:00:00Z',
        'device_id': '平板B',
        'data': AttendanceSync.staffToRow(staff, deviceId: 'x')['data'],
      });
      expect(remote.version, 7);
      expect(remote.deviceId, '平板B');
      expect(remote.updatedAt, DateTime.utc(2026, 9, 20, 12));
      expect(remote.staff.length, 2);
    });

    test('要不要拉服务器那份：本地改过就不拉；服务器版本更高才拉', () {
      expect(
        AttendanceSync.shouldPullStaff(
            serverVersion: 5, localVersion: 3, localDirty: false),
        isTrue,
      );
      expect(
        AttendanceSync.shouldPullStaff(
            serverVersion: 3, localVersion: 3, localDirty: false),
        isFalse,
      );
      expect(
        AttendanceSync.shouldPullStaff(
            serverVersion: 9, localVersion: 3, localDirty: true),
        isFalse,
        reason: '本地有没推上去的改动 → 先把本地的推上去（后改的赢）',
      );
    });
  });

  group('打卡记录', () {
    test('punchToRow：字段对，而且**不带** created_at（让数据库自己写）', () {
      final p = AttendancePunch(
        id: 'p1',
        employeeId: 'e1',
        kind: PunchKind.clockOut,
        at: DateTime(2026, 9, 21, 18, 30),
      );

      final row = AttendanceSync.punchToRow(p, deviceId: '收银台A');

      expect(row['id'], 'p1');
      expect(row['employee_id'], 'e1');
      expect(row['kind'], 'out');
      expect(row['device_id'], '收银台A');
      expect(row['at'], DateTime(2026, 9, 21, 18, 30).toIso8601String());
      expect(row.containsKey('created_at'), isFalse);
      expect(row.containsKey('pushed'), isFalse, reason: '本地字段不往上传');
    });

    test('punchFromRow：从服务器来的都算「已上传」，kind 认得出来', () {
      final p = AttendanceSync.punchFromRow({
        'id': 'p-other',
        'employee_id': 'e2',
        'kind': 'out',
        'at': '2026-09-21T18:30:00Z',
        'created_at': '2026-09-21T18:30:05Z',
        'device_id': '平板B',
      });
      expect(p.id, 'p-other');
      expect(p.employeeId, 'e2');
      expect(p.kind, PunchKind.clockOut);
      expect(p.pushed, isTrue);
      expect(p.at, DateTime.utc(2026, 9, 21, 18, 30));
    });

    test('老数据没有 kind → 当「上班」；没有 id → 用员工+时间推一个稳定 id', () {
      final p = AttendanceSync.punchFromRow({
        'employee_id': 'e1',
        'at': '2026-09-21T08:05:00Z',
      });
      expect(p.kind, PunchKind.clockIn);
      expect(p.id, startsWith('e1-'));
      // 同样的数据读两次 → id 一样（不然同步会重复记账）
      final again = AttendanceSync.punchFromRow({
        'employee_id': 'e1',
        'at': '2026-09-21T08:05:00Z',
      });
      expect(again.id, p.id);
    });

    test('punchCreatedAt：拿不到就给 0（不会把水位线往前推）', () {
      expect(
        AttendanceSync.punchCreatedAt({'created_at': '2026-09-21T08:05:00Z'}),
        DateTime.utc(2026, 9, 21, 8, 5),
      );
      expect(AttendanceSync.punchCreatedAt(const {}),
          DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
