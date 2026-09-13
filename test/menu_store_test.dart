import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:big_boss_bro/data/menu_store.dart';
import 'package:big_boss_bro/models/category.dart';
import 'package:big_boss_bro/models/menu_item.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MenuStore 保存后可读回（分类+菜品，含中文/价格）', () async {
    final store = MenuStore();
    final data = MenuData(
      categories: const [Category(id: 'c1', name: '热菜', emoji: '🍳')],
      items: const [
        MenuItem(
            id: 'i1', name: '牛肉炒饭', price: 28.0, emoji: '🍛', categoryId: 'c1'),
      ],
    );

    await store.save(data);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.categories.length, 1);
    expect(loaded.categories[0].name, '热菜');
    expect(loaded.items.length, 1);
    expect(loaded.items[0].name, '牛肉炒饭');
    expect(loaded.items[0].price, 28.0);
  });

  test('没有存过数据时 load 返回 null', () async {
    final store = MenuStore();
    expect(await store.load(), isNull);
  });
}
