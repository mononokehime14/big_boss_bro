import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/services/menu_importer.dart';

void main() {
  group('Excel 表 → 菜单', () {
    test('按表头识别分类/菜名；其余列两两一组做定制项', () {
      final rows = <List<String>>[
        ['种类', '菜品名字', '个性化定制项1', '定制1选项', '个性化定制项2', '定制2选项'],
        ['Vegetables', 'Verdura Cantones', 'Size', 'Mediano/Grande', '', ''],
        ['Vegetables', 'Chop suey de pollo', 'Size', 'Mediano/Grande', '辣度', '不辣/微辣/中辣'],
        ['Arroz', 'Arroz yangzhou', 'Size', 'Mediano/Grande', '', ''],
      ];
      final r = MenuImporter.fromRows(rows);

      expect(r.categoryCount, 2);
      expect(r.itemCount, 3);
      expect(r.optionGroupCount, 4); // Size×3 + 辣度×1

      final first = r.data.items.first;
      expect(first.name, 'Verdura Cantones');
      expect(first.options.length, 1);
      expect(first.options.first.name, 'Size');
      expect(first.options.first.options, ['Mediano', 'Grande']);

      final second = r.data.items[1];
      expect(second.options.length, 2);
      expect(second.options[1].name, '辣度');
      expect(second.options[1].options, ['不辣', '微辣', '中辣']);

      // 分类顺序按出现顺序
      expect(r.data.categories.map((c) => c.name).toList(),
          ['Vegetables', 'Arroz']);
    });

    test('价格列：支持 12,50（西语逗号）和 €9.90', () {
      final rows = <List<String>>[
        ['分类', '菜名', '价格', 'Size', 'Mediano/Grande'],
        ['Arroz', 'Arroz con pollo', '12,50', 'Size', 'Mediano/Grande'],
        ['Arroz', 'Arroz con res', '€9.90', 'Size', 'Mediano/Grande'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.data.items[0].price, closeTo(12.5, 0.001));
      expect(r.data.items[1].price, closeTo(9.9, 0.001));
    });

    test('没有价格列时给 0 并给出提醒', () {
      final rows = <List<String>>[
        ['分类', '菜名'],
        ['Arroz', 'A'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.data.items.first.price, 0);
      expect(r.warnings, isNotEmpty);
    });

    test('分类留空时跟随上一行', () {
      final rows = <List<String>>[
        ['分类', '菜名'],
        ['Arroz', 'A'],
        ['', 'B'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.itemCount, 2);
      expect(r.categoryCount, 1);
    });

    test('空表报错', () {
      expect(() => MenuImporter.fromRows(const []),
          throwsA(isA<MenuImportException>()));
    });

    test('每个分类都分到颜色，且**相邻分类颜色一定不同**', () {
      final rows = <List<String>>[
        ['分类', '菜名'],
        for (var i = 0; i < 12; i++) ['C$i', 'Item$i'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.categoryCount, 12);

      final cats = r.data.categories;
      for (var i = 0; i < cats.length; i++) {
        expect(cats[i].colorValue, isNot(0), reason: '第 $i 个分类应该有颜色');
        if (i > 0) {
          expect(cats[i].colorValue, isNot(cats[i - 1].colorValue),
              reason: '第 $i 个分类不应和上一个同色');
        }
      }
    });
  });

  group('真实样例 data/palacio_royal_09_12_2026.xlsx', () {
    test('能解析出 2 个分类 / 12 个菜品 / Size 定制项', () {
      final f = File('data/palacio_royal_09_12_2026.xlsx');
      expect(f.existsSync(), isTrue,
          reason: '样例 Excel 应该在 data/ 目录里（用于验证解析器）');

      final r = MenuImporter.fromXlsx(f.readAsBytesSync());

      expect(r.categoryCount, 2);
      expect(r.itemCount, 12);
      expect(r.optionGroupCount, 12); // 每道菜一组 Size
      expect(r.data.categories.map((c) => c.name).toList(),
          ['Vegetables', 'Arroz']);

      final first = r.data.items.first;
      expect(first.name, 'Verdura Cantones');
      expect(first.options.length, 1);
      expect(first.options.first.name, 'Size');
      expect(first.options.first.options, ['Mediano', 'Grande']);

      // 第二类第一道菜
      final arrozFirst =
          r.data.items.firstWhere((i) => i.name == 'Arroz yangzhou');
      expect(arrozFirst.options.first.options, ['Mediano', 'Grande']);
    });
  });
}
