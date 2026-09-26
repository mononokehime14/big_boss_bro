import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/app.dart';
import 'package:big_boss_bro/services/stub_print_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 冒烟测试：
/// 1. 没登录时**必须是登录页**（不能直接进收银界面）；
/// 2. 用默认管理员 `admin / 8888` 登录后进入点单界面。
///
/// 注意：`flutter create .` 会在 `test/` 里生成一个引用 `MyApp` 的
/// `widget_test.dart`。这里已经给了一份正确的，`flutter create` 不会覆盖已存在的文件。
void main() {
  testWidgets('未登录显示登录页，登录后进入点单界面', (tester) async {
    // 让 SharedPreferences 在测试里可用（否则 getInstance 会抛异常）
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      BigBossBroApp(printService: UnsupportedPrintService()),
    );
    // 等账号从本地读回来（读完才会出现默认管理员）
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // ① 登录页：有「登录」按钮，还没有底部导航
    expect(find.text('登录'), findsWidgets);
    expect(find.text('菜单'), findsNothing);

    // ② 输默认密码登录
    await tester.enterText(find.byType(TextField).first, '8888');
    await tester.tap(find.text('登录').last);
    await tester.pumpAndSettle();

    // ③ 进入点单界面（底部导航「菜单」可见）
    expect(find.text('菜单'), findsWidgets);
  });
}
