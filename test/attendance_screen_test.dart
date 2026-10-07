import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/screens/attendance_screen.dart';
import 'package:big_boss_bro/state/attendance_controller.dart';
import 'package:big_boss_bro/state/auth_controller.dart';

/// 签到页的界面测试：大按钮 → 数字键盘 → 打卡成功 → 名单里出现他。
///
/// 盯的是「员工实际会不会用」这条线：按钮在不在、点 4 下数字就完事、
/// 成功提示有没有把**姓名**写出来（没写的话员工不知道打上没有）。
void main() {
  testWidgets('签到页：点大按钮 → 输 4 位 PIN → 显示「签到成功 + 姓名」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final attendance = AttendanceController();
    await attendance.load();
    await attendance.addEmployee(name: '张三', pin: '1234');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AttendanceController>.value(value: attendance),
          ChangeNotifierProvider(create: (_) => AuthController()..load()),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // ① 大按钮在
    expect(find.byKey(const Key('clockin-button')), findsOneWidget);
    // 管理员区还没解锁（只显示那把「锁」）
    expect(find.text('员工管理'), findsNothing);

    // ② 点签到 → 数字键盘弹出来
    await tester.tap(find.byKey(const Key('clockin-button')));
    await tester.pumpAndSettle();
    expect(find.text('输入你的 PIN'), findsOneWidget);

    // ③ 点 1 2 3 4（满 4 位自动提交）
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // ④ 成功界面：勾 + 「签到成功」 + 姓名
    expect(find.byKey(const Key('clockin-done')), findsOneWidget);
    expect(find.text('签到成功'), findsOneWidget);
    expect(find.textContaining('张三'), findsWidgets);

    // ⑤ 1.8 秒后它自己关掉（手动把时间推过去，顺便避免留下未完成的 Timer）
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('输入你的 PIN'), findsNothing);

    // ⑥ 打卡真的记上了，而且出现在「今天已签到」里
    expect(attendance.punches.length, 1);
    expect(find.text('张三'), findsWidgets);
  });

  testWidgets('签到页：PIN 不对 → 就地提示，可以接着重输', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final attendance = AttendanceController();
    await attendance.load();
    await attendance.addEmployee(name: '张三', pin: '1234');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AttendanceController>.value(value: attendance),
          ChangeNotifierProvider(create: (_) => AuthController()..load()),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clockin-button')));
    await tester.pumpAndSettle();

    // 输一个错的 PIN
    for (final d in ['9', '9', '9', '9']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('PIN 不对，再试一次'), findsOneWidget);
    expect(find.byKey(const Key('clockin-done')), findsNothing);
    expect(attendance.punches, isEmpty, reason: '错的 PIN 不能记账');

    // 接着输对的 → 成功（不用重新点一次「签到」）
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clockin-done')), findsOneWidget);
    expect(attendance.punches.length, 1);

    // 收尾（把自动关闭的 Timer 走完）
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
