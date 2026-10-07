import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee.dart';

/// **员工 + 打卡记录**的本地存储（shared_preferences + JSON，跟账号/订单一个做法）。
///
/// 两个键分开存：员工列表、打卡记录。读的时候坏数据就当空的（不让一条坏 JSON
/// 把整个签到页搞崩）。
class EmployeeStore {
  static const _kEmployees = 'attendance_employees';
  static const _kPunches = 'attendance_punches';

  /// 打卡记录最多留这么多条（一天几个人打一次，5000 条够用很久了；
  /// 防止哪天出现异常数据把存储撑爆）。
  static const int maxPunches = 5000;

  Future<List<Employee>> loadEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(
      prefs.getString(_kEmployees),
      (m) => Employee.fromJson(m),
    );
  }

  Future<List<AttendancePunch>> loadPunches() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(
      prefs.getString(_kPunches),
      (m) => AttendancePunch.fromJson(m),
    );
  }

  Future<void> saveEmployees(List<Employee> employees) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kEmployees,
      jsonEncode(employees.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> savePunches(List<AttendancePunch> punches) async {
    final prefs = await SharedPreferences.getInstance();
    // 只留最近的 maxPunches 条（列表本身是按时间追加的，取尾巴即可）
    final keep = punches.length > maxPunches
        ? punches.sublist(punches.length - maxPunches)
        : punches;
    await prefs.setString(
      _kPunches,
      jsonEncode(keep.map((p) => p.toJson()).toList()),
    );
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic> map) fromJson,
  ) {
    if (raw == null) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      // 坏数据当空
    }
    return <T>[];
  }
}
