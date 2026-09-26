import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/data/settings_store.dart';

void main() {
  group('备注按种类分组', () {
    test('通用备注所有种类都能用；分类备注只归自己', () {
      final s = Settings();
      s.addNote('', '米饭换面条'); // 通用
      s.addNote('drink', '加冰'); // 只有饮料有
      s.addNote('drink', '少糖');

      expect(s.notesFor('drink'), ['米饭换面条', '加冰', '少糖']);
      expect(s.notesFor('hot'), ['米饭换面条']); // 热菜看不到「加冰」
      expect(s.notesFor('unknown'), ['米饭换面条']);
    });

    test('重复添加不会重复；删除只删指定分类的', () {
      final s = Settings();
      s.addNote('drink', '加冰');
      s.addNote('drink', '加冰');
      expect(s.notesFor('drink'), ['加冰']);

      s.removeNote('drink', '加冰');
      expect(s.notesFor('drink'), isEmpty);
    });
  });

  group('日结支出', () {
    test('存/取/清零', () {
      final s = Settings();
      expect(s.expenseFor('2026-01-01'), 0);
      s.setExpense('2026-01-01', 120.5);
      expect(s.expenseFor('2026-01-01'), 120.5);
      s.setExpense('2026-01-01', 0);
      expect(s.expenseFor('2026-01-01'), 0);
      expect(s.dailyExpenses.containsKey('2026-01-01'), isFalse);
    });
  });

  test('菜品管理默认密码是 8888', () {
    expect(Settings().menuPassword, '8888');
    expect(kDefaultMenuPassword, '8888');
  });

  group('本轮新增的两个设置', () {
    test('店头信息默认空（老用户的小票排版不变）', () {
      expect(Settings().storeHeader, '');
    });

    test('厨师单字体大小默认 1 = 正常（老用户打出来跟以前一模一样）', () {
      expect(Settings().kitchenFontSize, 1);
    });
  });
}
