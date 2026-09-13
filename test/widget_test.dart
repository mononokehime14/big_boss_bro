import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/app.dart';
import 'package:big_boss_bro/services/stub_print_service.dart';

/// 冒烟测试：App 能启动，并显示底部「菜单」标签。
///
/// 注意：`flutter create .` 会在 `test/` 里生成一个引用 `MyApp` 的
/// `widget_test.dart`。这里已经给了一份正确的，`flutter create` 不会覆盖已存在的文件。
void main() {
  testWidgets('应用启动后显示点单界面', (tester) async {
    // 让 SharedPreferences 在测试里可用（否则 getInstance 会抛异常）
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      BigBossBroApp(printService: UnsupportedPrintService()),
    );
    await tester.pump();

    // 底部导航「菜单」标签一定可见（nav.menu）
    expect(find.text('菜单'), findsWidgets);
  });
}
