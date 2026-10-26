import '../models/category.dart';
import '../models/menu_item.dart';

/// 把当前菜单**导出成和导入模板同列**的二维表。
///
/// 列顺序（表头按这个顺序写；`MenuImporter` 是按表头名字认列的，所以顺序
/// 其实不敏感，但固定下来方便老板在 Excel 里看）：
///
/// ```
/// 种类 | 菜品名字 | 菜品昵称 | 基础价格 | 基础数量 | 单位 | 图标
/// | 个性化定制项1 | 定制1选项 | 定制1选项价格
/// | 个性化定制项2 | 定制2选项 | 定制2选项价格 | ...
/// ```
///
/// 定制项列数 = 所有菜里**最多**的那道菜的定制项数量；没那么多定制项的菜
/// 后面留空。
class MenuExporter {
  const MenuExporter._();

  static List<List<String>> rows(
    List<Category> categories,
    List<MenuItem> menu,
  ) {
    // 分类按菜单里的分类顺序分组；同分类内保持原来的菜顺序。
    final catOrder = <String, int>{
      for (var i = 0; i < categories.length; i++) categories[i].id: i,
    };
    final catName = <String, String>{
      for (final c in categories) c.id: c.name,
    };
    final indexed = <({MenuItem item, int index})>[
      for (var i = 0; i < menu.length; i++) (item: menu[i], index: i),
    ];
    indexed.sort((a, b) {
      final ca = catOrder[a.item.categoryId] ?? categories.length;
      final cb = catOrder[b.item.categoryId] ?? categories.length;
      if (ca != cb) return ca.compareTo(cb);
      return a.index.compareTo(b.index);
    });

    var maxGroups = 0;
    for (final it in menu) {
      if (it.options.length > maxGroups) maxGroups = it.options.length;
    }

    final header = <String>[
      '种类',
      '菜品名字',
      '菜品昵称',
      '基础价格',
      '基础数量',
      '单位',
      '图标',
      for (var i = 1; i <= maxGroups; i++) ...[
        '个性化定制项$i',
        '定制${i}选项',
        '定制${i}选项价格',
      ],
    ];

    final out = <List<String>>[header];
    for (final e in indexed) {
      final it = e.item;
      final row = <String>[
        catName[it.categoryId] ?? it.categoryId,
        it.name,
        it.nickName,
        _num(it.price),
        it.minQuantity.toString(),
        it.unit,
        it.emoji,
      ];
      for (var i = 0; i < maxGroups; i++) {
        if (i >= it.options.length) {
          row.addAll(const ['', '', '']);
          continue;
        }
        final g = it.options[i];
        row
          ..add(g.name)
          ..add(g.options.join('/'))
          ..add(g.prices.isEmpty
              ? ''
              : g.prices.map(_num).toList().join('/'));
      }
      out.add(row);
    }
    return out;
  }

  /// 导出文件名：`menu_2026-10-25_1714.xlsx`。
  static String fileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'menu_${d.year}-${two(d.month)}-${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}.xlsx';
  }

  /// 价格写成 `28` / `12.5`（不写货币符号；Excel 里也能直接改）。
  static String _num(double v) {
    if ((v - v.roundToDouble()).abs() < 0.005) return v.round().toString();
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
