import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/settings_store.dart';

void main() {
  setUp(() {
    // 存/读设置的测试要用 SharedPreferences（测试里没插件 → 得用假数据）
    SharedPreferences.setMockInitialValues({});
  });
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

  // 常用备注也能**带加价**（「换炒饭 +70」）：设置里那条备注后面那个小金额框。
  group('常用备注的加价', () {
    test('存加价 / 查加价 / 不加价就是 0', () {
      final s = Settings();
      s.addNote('hot', '换炒饭', price: 70);
      s.addNote('hot', '少辣'); // 没填金额 = 不改价
      expect(s.notePriceFor('hot', '换炒饭'), 70);
      expect(s.notePriceFor('hot', '少辣'), 0);
      expect(s.notePriceFor('hot', '没有这条'), 0);
    });

    test('同一条备注再加一次 = 改它的加价；填 0 = 改回不改价', () {
      final s = Settings();
      s.addNote('hot', '换炒饭', price: 70);
      s.addNote('hot', '换炒饭', price: 50);
      expect(s.notePriceFor('hot', '换炒饭'), 50);
      expect(s.notesFor('hot'), ['换炒饭']); // 不会变成两条

      s.addNote('hot', '换炒饭', price: 0);
      expect(s.notePriceFor('hot', '换炒饭'), 0);
      expect(s.notePricesByCategory.containsKey('hot'), isFalse,
          reason: '0 的不用记（省得存一堆没用的）');
    });

    test('通用（""）的加价对所有种类生效；分类自己的优先', () {
      final s = Settings();
      s.addNote('', '加饭', price: 10);
      expect(s.notePriceFor('drink', '加饭'), 10);
      expect(s.notePriceFor('', '加饭'), 10);

      // 同一个名字在某个分类下另定一个价 → 那个分类用自己那份
      s.addNote('drink', '加饭', price: 15);
      expect(s.notePriceFor('drink', '加饭'), 15);
      expect(s.notePriceFor('hot', '加饭'), 10);
    });

    test('删掉这条备注，加价也一起删', () {
      final s = Settings();
      s.addNote('hot', '换炒饭', price: 70);
      s.removeNote('hot', '换炒饭');
      expect(s.notesFor('hot'), isEmpty);
      expect(s.notePriceFor('hot', '换炒饭'), 0);
      expect(s.notePricesByCategory.containsKey('hot'), isFalse);
    });

    test('加价能存住（重启 App 还在）', () async {
      final store = SettingsStore();
      final s = Settings()..addNote('hot', '换炒饭', price: 70);
      await store.save(s);

      final back = await store.load();
      expect(back.notesFor('hot'), ['换炒饭']);
      expect(back.notePriceFor('hot', '换炒饭'), 70);
    });

    test('老数据（没有加价这个字段）读回来 = 所有备注都不改价', () async {
      // 只存了备注文字、没有 note_prices_by_category 那种老存档
      SharedPreferences.setMockInitialValues({
        'notes_by_category': '{"hot":["少辣"]}',
      });
      final back = await SettingsStore().load();
      expect(back.notesFor('hot'), ['少辣']);
      expect(back.notePriceFor('hot', '少辣'), 0);
      expect(back.notePricesByCategory, isEmpty);
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

  group('打印相关的默认值', () {
    test('店头信息默认空（老用户的小票排版不变）', () {
      expect(Settings().storeHeader, '');
    });

    // 厨师单菜品字号**不再是设置项**：写死在 `receipt_layout.dart` 的
    // `kKitchenItemScale`（特大 = 双倍宽 + 双倍高），设置页里已经没有这一项了。
    test('厨师单默认打 2 张（厨师 1 张 + 出餐服务员 1 张）', () {
      expect(Settings().kitchenCopies, 2);
    });
  });
}
