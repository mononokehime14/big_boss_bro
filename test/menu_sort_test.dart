import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/models/category.dart';
import 'package:big_boss_bro/models/menu_item.dart';
import 'package:big_boss_bro/utils/menu_sort.dart';

/// 点单区的排序规则（默认 / 首字母 / 流行度）。
void main() {
  Category cat(String id, String name) => Category(id: id, name: name);
  MenuItem item(String id, String name, String catId) =>
      MenuItem(id: id, name: name, price: 10, emoji: '', categoryId: catId);

  group('MenuSort', () {
    test('id 与枚举互转；认不出的 id 当「默认」', () {
      expect(MenuSort.fromId('popular'), MenuSort.popular);
      expect(MenuSort.fromId('name'), MenuSort.name);
      expect(MenuSort.fromId('default'), MenuSort.natural);
      expect(MenuSort.fromId('说什么呢'), MenuSort.natural);
      expect(MenuSort.fromId(null), MenuSort.natural);
    });
  });

  group('菜品的排序', () {
    final items = [
      item('1', 'CHOW MEIN POLLO', 'hot'),
      item('2', 'arroz con camaron', 'hot'),
      item('3', 'SOPA', 'hot'),
    ];

    test('默认：不动，保持菜单（Excel）的顺序', () {
      final out = sortMenuItems(items, MenuSort.natural, {});
      expect(out.map((m) => m.id).toList(), ['1', '2', '3']);
    });

    test('首字母：A→Z，大小写不敏感', () {
      final out = sortMenuItems(items, MenuSort.name, {});
      expect(out.map((m) => m.name).toList(),
          ['arroz con camaron', 'CHOW MEIN POLLO', 'SOPA']);
    });

    test('流行度：份数多的在前；一样多就按名字', () {
      final out = sortMenuItems(items, MenuSort.popular, {'3': 10, '1': 3});
      expect(out.map((m) => m.id).toList(), ['3', '1', '2']);
    });

    test('排序不会动到原来的列表', () {
      final copy = List.of(items);
      sortMenuItems(items, MenuSort.name, {});
      expect(items.map((m) => m.id).toList(), copy.map((m) => m.id).toList());
    });
  });

  group('种类的排序', () {
    final cats = [
      cat('hot', '热菜'),
      cat('drink', 'Bebidas'),
      cat('staple', 'Alimentos'),
    ];

    test('默认：原顺序', () {
      expect(sortCategories(cats, MenuSort.natural, {}).map((c) => c.id),
          ['hot', 'drink', 'staple']);
    });

    test('首字母：A→Z（西语名就是字母顺序）', () {
      expect(sortCategories(cats, MenuSort.name, {}).map((c) => c.name),
          ['Alimentos', 'Bebidas', '热菜']); // 中文按码位排在后面
    });

    test('流行度：卖得多的分类在前', () {
      final out = sortCategories(cats, MenuSort.popular, {'staple': 20, 'hot': 5});
      expect(out.map((c) => c.id), ['staple', 'hot', 'drink']);
    });
  });
}
