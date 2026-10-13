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

  group('默认排序 = 本机记住的顺序（拖动排出来的）', () {
    final items = [
      item('1', 'CHOW MEIN POLLO', 'hot'),
      item('2', 'arroz con camaron', 'hot'),
      item('3', 'SOPA', 'hot'),
    ];

    test('顺序表是空的时候 = 菜单原本的顺序（还没拖过）', () {
      final out = sortMenuItems(items, MenuSort.natural, {});
      expect(out.map((m) => m.id).toList(), ['1', '2', '3']);
    });

    test('有顺序表就按它排；没排过的排在最后、而且保持原先后', () {
      final out = sortMenuItems(items, MenuSort.natural, {}, order: ['3', '1']);
      expect(out.map((m) => m.id).toList(), ['3', '1', '2']);
    });

    test('种类也用同一张表排', () {
      final cats2 = [
        cat('hot', '热菜'),
        cat('drink', 'Bebidas'),
        cat('staple', 'Alimentos'),
      ];
      final out =
          sortCategories(cats2, MenuSort.natural, {}, order: ['staple', 'hot']);
      expect(out.map((c) => c.id).toList(), ['staple', 'hot', 'drink']);
    });

    test('老版本存过的 custom 一律当「默认」（拖好的顺序不会丢）', () {
      expect(MenuSort.fromId('custom'), MenuSort.natural);
    });

    test('拖动：把 c 拖到 a 上 → c 变成第一个', () {
      expect(moveBefore(['a', 'b', 'c'], 'c', 'a'), ['c', 'a', 'b']);
      expect(moveBefore(['a', 'b', 'c'], 'a', 'c'), ['b', 'a', 'c']);
      // 拖到自己头上 = 什么都不动
      expect(moveBefore(['a', 'b', 'c'], 'a', 'a'), ['a', 'b', 'c']);
      // 表外的 id（比如新导入的菜）也能插进去
      expect(moveBefore(['a', 'b'], 'x', 'b'), ['a', 'x', 'b']);
    });

    test('写回全局表：拖过的那一组挪到表尾，别组的 id 一个不丢', () {
      final stored = ['drink', 'hot', 'cola', 'taco'];
      final out = applyVisibleOrder(stored, ['hot', 'drink']);
      expect(out, ['cola', 'taco', 'hot', 'drink']);
      expect(out.toSet(), stored.toSet());
    });
  });

  group('桌号的自然顺序', () {
    test('数字按数值大小：1,2,9,10（不是按字符串的 1,10,2）', () {
      expect(sortedTables(['10', '2', '1', '9']), ['1', '2', '9', '10']);
    });

    test('数字在前，然后是字母（A,B,C…SA,SB）', () {
      expect(sortedTables(['C', 'A', '3', '1', 'B', 'SB', 'SA']),
          ['1', '3', 'A', 'B', 'C', 'SA', 'SB']);
    });

    test('大小写不敏感；字母+数字的按段比', () {
      expect(sortedTables(['a1', 'A2', 'A10']), ['a1', 'A2', 'A10']);
      expect(sortedTables(['B', 'a']), ['a', 'B']);
    });

    test('不动传进来的列表', () {
      final src = ['2', '1'];
      sortedTables(src);
      expect(src, ['2', '1']);
    });
  });
}
