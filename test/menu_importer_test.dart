import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/services/menu_importer.dart';
import 'package:big_boss_bro/services/xlsx_reader.dart';

void main() {
  group('Excel 表 → 菜单', () {
    test('两列一组：定制项名 + 选项（用 / 分隔）', () {
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

      expect(r.data.categories.map((c) => c.name).toList(),
          ['Vegetables', 'Arroz']);
    });

    test('三列一组：定制项 + 选项 + **每个选项的加价**', () {
      final rows = <List<String>>[
        ['种类', '菜品名字', '基础价格', '定制项1', '定制1选项', '定制1选项价格'],
        ['Arroz', 'Arroz con pollo', '100', 'Size', 'Mediano/Grande', '0/50'],
        ['Arroz', 'Arroz con res', '120', 'Size', 'Mediano/Grande', '10/60'],
      ];
      final r = MenuImporter.fromRows(rows);

      expect(r.itemCount, 2);
      final a = r.data.items[0];
      expect(a.price, 100); // 基础价格
      expect(a.options.length, 1);
      expect(a.options.first.name, 'Size');
      expect(a.options.first.options, ['Mediano', 'Grande']);
      expect(a.options.first.prices, [0, 50]);
      expect(a.options.first.hasPrices, isTrue);
      // 单价 = 基础价 + 所选加价
      expect(a.unitPriceFor(['Mediano']), 100);
      expect(a.unitPriceFor(['Grande']), 150);
      expect(a.minUnitPrice, 100);
      // 第二道菜
      final b = r.data.items[1];
      expect(b.unitPriceFor(['Grande']), 180);
    });

    test('选项价格数量不足时补 0，不会错位', () {
      final rows = <List<String>>[
        ['分类', '菜名', '基础价格', 'Size', '定制1选项', '定制1选项价格'],
        ['Arroz', 'A', '100', 'Size', 'Mediano/Grande/Chico', '0/50'],
      ];
      final r = MenuImporter.fromRows(rows);
      final g = r.data.items.first.options.first;
      expect(g.options.length, 3);
      expect(g.prices, [0, 50, 0]); // 第三个没给 → 0
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

    test('「基础数量」列：认出它并写进 minQuantity，**不能**被当成定制项', () {
      // 真实场景：表里有 种类 / 菜名 / 基础价格 / **基础数量** / 定制项1 / 选项 / 选项价格
      final rows = <List<String>>[
        ['种类', '菜品名字', '基础价格', '基础数量', '个性化定制项1', '定制1选项', '定制1选项价格'],
        ['Paquete', 'Paquete Familiar #1', '260', '2', 'Size', 'Mediano/Grande', '0/50'],
        ['Arroz', 'Arroz con pollo', '100', '1', 'Size', 'Mediano/Grande', '0/50'],
        // 最后一行：**基础数量留空**（不是每种菜都填），但一样有 Size 定制项
        ['Arroz', 'Sin cantidad', '80', '', 'Size', 'Mediano/Grande', '0/50'],
      ];
      final r = MenuImporter.fromRows(rows);

      // 关键回归：「基础数量」列**不能**被当成一组定制项
      //（被误认时每组会多出「2 / Size」和「定制1选项 / 0/50」两组，这里就会挂）
      expect(r.optionGroupCount, 3, reason: '三道菜各一组 Size，多出来就是把列认歪了');
      for (final it in r.data.items) {
        expect(it.options.length, 1, reason: '${it.name} 应该只有 Size 一组定制项');
        expect(it.options.first.name, 'Size');
        expect(it.options.first.name.contains('数量'), isFalse,
            reason: '「基础数量」列被误当成定制项了');
        expect(it.options.first.options, ['Mediano', 'Grande']);
      }

      expect(r.data.items[0].minQuantity, 2); // 2 份起
      expect(r.data.items[1].minQuantity, 1);
      expect(r.data.items[2].minQuantity, 1); // 空着 → 1
      expect(r.data.items[0].hasMinQuantity, isTrue);
      expect(r.data.items[1].hasMinQuantity, isFalse);
      // 价格不受影响
      expect(r.data.items[0].price, 260);
    });

    test('没有「基础数量」列时，minQuantity 一律是 1', () {
      final rows = <List<String>>[
        ['分类', '菜名', '价格'],
        ['Arroz', 'A', '100'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.data.items.first.minQuantity, 1);
    });

    test('「菜品昵称」列：认出来写进 nickName；**不能**被当成定制项', () {
      // 真实表头顺序：种类 | 菜品名字 | 菜品昵称 | 基础价格 | 基础数量 | 定制项1 | 选项 | 选项价格
      // ⚠️ 昵称列右边紧跟定制项，认漏了整张表的定制项都会歪（真实踩过）
      final rows = <List<String>>[
        ['种类', '菜品名字', '菜品昵称', '基础价格', '基础数量', '个性化定制项1', '定制1选项', '定制1选项价格'],
        ['LONCHE', 'Lonche #1 Chop Suey de pollo', 'L #1', '160', '1', 'Size', 'Mediano/Grande', '140/185'],
        ['LONCHE', 'Lonche #2 Pollo cantones', '', '160', '1', 'Size', 'Mediano/Grande', '140/185'],
      ];
      final r = MenuImporter.fromRows(rows);

      expect(r.itemCount, 2);
      // 昵称读到了
      expect(r.data.items[0].nickName, 'L #1');
      expect(r.data.items[0].displayName, 'L #1'); // 有昵称 → 显示昵称
      // 空昵称 → 显示全名
      expect(r.data.items[1].nickName, '');
      expect(r.data.items[1].displayName, 'Lonche #2 Pollo cantones');
      // 关键回归：昵称列没被当成一组定制项（每道菜只有 Size 一组）
      for (final it in r.data.items) {
        expect(it.options.length, 1, reason: '${it.name} 应该只有 Size 一组定制项');
        expect(it.options.first.name, 'Size');
        expect(it.options.first.name.contains('昵称'), isFalse,
            reason: '「菜品昵称」列被误当成定制项了');
        expect(it.options.first.options, ['Mediano', 'Grande']);
      }
      // 基础价没被昵称列带歪
      expect(r.data.items[0].price, 160);
    });

    test('定制项**可以有三组**（昵称列存在时也不能漏）', () {
      final rows = <List<String>>[
        [
          '种类', '菜品名字', '菜品昵称', '基础价格', '基础数量',
          '个性化定制项1', '定制1选项', '定制1选项价格',
          '个性化定制项2', '定制2选项', '定制2选项价格',
          '个性化定制项3', '定制3选项', '定制3选项价格',
        ],
        [
          'CALDOS', 'Caldo De Verdura', 'Caldo Verdura', '0', '1',
          'Size', 'Chico/Mediano/Grande', '50/120/180',
          'con Noodle', 'con Noodle', '50',
          'con Hefen', 'con Hefen', '70',
        ],
      ];
      final r = MenuImporter.fromRows(rows);

      expect(r.optionGroupCount, 3, reason: '三组定制项都要认出来');
      final it = r.data.items.single;
      expect(it.nickName, 'Caldo Verdura');
      expect(it.options.length, 3);
      expect(it.options[0].name, 'Size');
      expect(it.options[0].options, ['Chico', 'Mediano', 'Grande']);
      expect(it.options[0].prices, [50, 120, 180]);
      expect(it.options[1].name, 'con Noodle');
      expect(it.options[1].options, ['con Noodle']);
      expect(it.options[1].prices, [50]);
      expect(it.options[2].name, 'con Hefen');
      expect(it.options[2].prices, [70]);
      // 三组都能加钱：基础价 0 + 三个选项
      expect(it.unitPriceFor(['Grande', 'con Noodle', 'con Hefen']), 300);
    });

    test('没有昵称列时，nickName 空、displayName 回退到全名', () {
      final rows = <List<String>>[
        ['分类', '菜名', '价格'],
        ['Arroz', 'Arroz con pollo', '100'],
      ];
      final r = MenuImporter.fromRows(rows);
      expect(r.data.items.first.nickName, '');
      expect(r.data.items.first.displayName, 'Arroz con pollo');
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
    // 这份文件会持续更新（分类/菜品/菜名都会变），所以**不写死行数和第一道菜**，
    // 只验证「结构正确」和几个必须成立的事实。
    test('关键列按表头认；定制项 1/2… 右边跟着选项和价格', () {
      final f = File('data/palacio_royal_09_12_2026.xlsx');
      expect(f.existsSync(), isTrue,
          reason: '样例 Excel 应该在 data/ 目录里（用于验证解析器）');
      final bytes = f.readAsBytesSync();

      final r = MenuImporter.fromXlsx(bytes);

      expect(r.categoryCount, greaterThan(1));
      expect(r.itemCount, greaterThan(10));

      // 每个分类都有颜色
      for (final c in r.data.categories) {
        expect(c.colorValue, isNot(0), reason: '分类 ${c.name} 应该有颜色');
      }

      // 每道菜的所属分类都必须存在、名字不能空
      final ids = r.data.categories.map((c) => c.id).toSet();
      for (final it in r.data.items) {
        expect(ids.contains(it.categoryId), isTrue,
            reason: '${it.name} 的分类不存在');
        expect(it.name.trim(), isNotEmpty);
      }

      // 定制项名字不能是空的，也不能把「选项 / 选项价格」两列误当成定制项名
      for (final it in r.data.items) {
        for (final g in it.options) {
          expect(g.name.trim(), isNotEmpty, reason: '${it.name} 的定制项没有名字');
          expect(g.name.contains('价格'), isFalse,
              reason: '价格列被误当成定制项了：${g.name}');
          expect(g.name.contains('选项'), isFalse,
              reason: '选项列被误当成定制项名了：${g.name}');
          // 回归：表里新加的「基础数量」列**不能**被当成一组定制项
          expect(g.name.contains('数量'), isFalse,
              reason: '「基础数量」列被误当成定制项了：${g.name}');
          // 回归：新加的「菜品昵称」列**也不能**被当成一组定制项
          //（它的表头里有「菜品」两个字，而且右边紧跟定制项，认漏了整张表都会歪）
          expect(g.name.contains('昵称'), isFalse,
              reason: '「菜品昵称」列被误当成定制项了：${g.name}');
        }
      }

      // 「菜品昵称」列：有昵称的菜，displayName 用昵称；没昵称的用全名
      final nicknamed =
          r.data.items.where((it) => it.nickName.trim().isNotEmpty).toList();
      expect(nicknamed, isNotEmpty, reason: '样例里有「菜品昵称」列，应该有菜带昵称');
      for (final it in nicknamed) {
        expect(it.displayName, it.nickName.trim());
      }
      for (final it in r.data.items.where((it) => it.nickName.trim().isEmpty)) {
        expect(it.displayName, it.name, reason: '没昵称就应该显示全名');
      }

      // 定制项：**组数跟着 Excel 数据走，不写死**。
      // 2026-10 这版样例里「定制项 1/2/3」三组**表头都在，但数据只填了第 1 组**
      // （以前 Combinacion China 那种 "Size + con Noodle + con Hefen" 的三组菜被删了），
      // 所以这里不再断言"必须有多组"。多组解析由上面那条 `fromRows` 的
      // 「定制项**可以有三组**」守着（那条不依赖这个文件）。
      final withOptions =
          r.data.items.where((it) => it.options.isNotEmpty).toList();
      expect(withOptions, isNotEmpty, reason: '样例里有带定制项的菜');
      for (final it in withOptions) {
        for (final g in it.options) {
          expect(g.name.trim(), isNotEmpty,
              reason: '${it.name} 的定制项没有名字');
          expect(g.options, isNotEmpty,
              reason: '${it.name} 的「${g.name}」一个选项都没有');
          // 价格要么跟选项一一对应，要么整组没价格（两列一组那种老表）
          expect(g.prices.isEmpty || g.prices.length == g.options.length, isTrue,
              reason: '${it.name} 的「${g.name}」价格和选项数量对不上：'
                  '${g.options} / ${g.prices}');
        }
        // 表里最多就三组定制项：解析器**不能凭空造出第 4 组**空组来
        expect(it.options.length, lessThanOrEqualTo(3),
            reason: '${it.name} 解析出了 ${it.options.length} 组定制项');
      }

      // 「基础数量」列：每道菜至少 1 份起（没这一列时默认也是 1）
      for (final it in r.data.items) {
        expect(it.minQuantity, greaterThanOrEqualTo(1),
            reason: '${it.name} 的最少份数不对');
      }

      // 抽查一道菜（VERDURA CANTONES，Vegetables）：一组 Size，**每个选项都带价格**
      final verdura = r.data.items.firstWhere(
        (it) => it.name.toUpperCase().contains('VERDURA CANTONES'),
        orElse: () => throw StateError('样例里应该有 VERDURA CANTONES'),
      );
      expect(verdura.options.length, 1);
      final size = verdura.options.first;
      expect(size.name, 'Size');
      expect(size.options, ['Mediano', 'Grande']);
      expect(size.prices.length, 2);
      expect(size.prices.every((p) => p > 0), isTrue,
          reason: '样例里 Size 的每个选项都带价格');

      // 单价 = 基础价 + 选中项加价
      expect(verdura.unitPriceFor(['Grande']), verdura.price + size.prices[1]);
      expect(verdura.unitPriceFor(['Mediano']), verdura.price + size.prices[0]);

      // 回归：**「定制项」名字那一格留空的行也要认出来**
      //（样例里 Carnitas/Chorizo 那两行就没写名字）
      // 办法：直接数 Excel 里「选项」列有内容的行数，导入后有定制项的菜数应该一样多。
      final rows = XlsxReader.readFirstSheet(bytes);
      var headerIdx = 0;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].any((c) => c.contains('种类'))) {
          headerIdx = i;
          break;
        }
      }
      final optCol = rows[headerIdx]
          .indexWhere((h) => h.contains('选项') && !h.contains('价格'));
      expect(optCol, greaterThanOrEqualTo(0), reason: '样例里应该有「定制1选项」列');

      var rowsWithOptions = 0;
      for (var i = headerIdx + 1; i < rows.length; i++) {
        final row = rows[i];
        if (optCol < row.length && row[optCol].trim().isNotEmpty) {
          rowsWithOptions++;
        }
      }
      final itemsWithOptions =
          r.data.items.where((it) => it.options.isNotEmpty).length;
      expect(itemsWithOptions, rowsWithOptions,
          reason: '每一行有选项的菜都要有定制项（哪怕「定制项」那格是空的）');
      expect(rowsWithOptions, greaterThan(0));
    });
  });
}
