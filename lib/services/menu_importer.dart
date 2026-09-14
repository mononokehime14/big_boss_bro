import '../data/menu_store.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/menu_option_group.dart';
import '../utils/category_colors.dart';
import 'xlsx_reader.dart';

/// 导入结果摘要（用于给用户看“读到了什么”）。
class MenuImportResult {
  final MenuData data;
  final int categoryCount;
  final int itemCount;
  final int optionGroupCount;
  final List<String> warnings;

  const MenuImportResult({
    required this.data,
    required this.categoryCount,
    required this.itemCount,
    required this.optionGroupCount,
    required this.warnings,
  });
}

class MenuImportException implements Exception {
  final String message;
  const MenuImportException(this.message);
  @override
  String toString() => message;
}

/// 把菜单 Excel 解析成菜单数据。
///
/// 支持的表格布局（列的顺序不固定，按**表头名字**识别）：
/// - 分类列：`种类` / `类别` / `分类` / `category` / `categoria`
/// - 菜名列：`菜品名字` / `菜名` / `名称` / `name` / `nombre`
/// - 价格列（可选）：`价格` / `单价` / `price` / `precio`（支持 `12,50` 这种西语写法）
/// - 图标列（可选）：`图标` / `emoji` / `icon`
/// - **其余列两两一组**：`(定制项名, 选项列表)`，选项用 `/` 分隔
///   例如 `Size` + `Mediano/Grande` → 定制项 Size，选项 [Mediano, Grande]
class MenuImporter {
  /// 从 .xlsx 字节导入。
  static MenuImportResult fromXlsx(List<int> bytes, {String idPrefix = 'x'}) {
    final rows = XlsxReader.readFirstSheet(bytes);
    return fromRows(rows, idPrefix: idPrefix);
  }

  /// 从二维表导入（便于单测）。
  static MenuImportResult fromRows(
    List<List<String>> rows, {
    String idPrefix = 'x',
  }) {
    final warnings = <String>[];

    // 1) 找表头行：第一条「非空单元格 >= 2」的行
    var headerIdx = -1;
    for (var i = 0; i < rows.length; i++) {
      final nonEmpty = rows[i].where((c) => c.trim().isNotEmpty).length;
      if (nonEmpty >= 2) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) {
      throw const MenuImportException('Excel 里没读到内容（表头都没有）。');
    }
    final header = rows[headerIdx];

    // 2) 识别每一列的角色
    int? catCol, nameCol, priceCol, iconCol;
    final pairCols = <int>[];
    for (var c = 0; c < header.length; c++) {
      final h = header[c].trim().toLowerCase();
      if (h.isEmpty) continue;
      if (catCol == null && _isCategoryHeader(h)) {
        catCol = c;
        continue;
      }
      if (nameCol == null && _isNameHeader(h)) {
        nameCol = c;
        continue;
      }
      if (priceCol == null && _isPriceHeader(h)) {
        priceCol = c;
        continue;
      }
      if (iconCol == null && _isIconHeader(h)) {
        iconCol = c;
        continue;
      }
      pairCols.add(c);
    }
    if (catCol == null) catCol = 0;
    if (nameCol == null) nameCol = (catCol == 0) ? 1 : 0;
    if (priceCol == null) {
      warnings.add('没有找到「价格」列 → 菜品价格先按 0 处理；'
          '可以在 Excel 里加一列「价格」，或在 App 的「菜品管理」里逐个改。');
    }

    // 3) 剩下的列两两配对成定制项（名称列, 选项列）
    final pairs = <List<int>>[];
    for (var i = 0; i + 1 < pairCols.length; i += 2) {
      pairs.add([pairCols[i], pairCols[i + 1]]);
    }

    // 4) 逐行读菜品
    final categories = <Category>[];
    final catIdByName = <String, String>{};
    final items = <MenuItem>[];
    var optionGroupCount = 0;
    var counter = 0;
    var lastCategory = '';

    for (var r = headerIdx + 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int? i) =>
          (i != null && i >= 0 && i < row.length) ? row[i].trim() : '';

      final rawCat = cell(catCol);
      final name = cell(nameCol);
      if (rawCat.isEmpty && name.isEmpty) continue;

      // 分类允许多行留空（跟随上一行）
      final catName = rawCat.isNotEmpty ? rawCat : lastCategory;
      if (catName.isEmpty) {
        if (name.isNotEmpty) warnings.add('第 ${r + 1} 行没有分类，已跳过：$name');
        continue;
      }
      lastCategory = catName;
      if (name.isEmpty) continue;

      if (!catIdByName.containsKey(catName)) {
        final id = 'c${catIdByName.length + 1}';
        catIdByName[catName] = id;
        // 每个分类分配一个底色：按顺序轮换调色板 → 相邻分类必然不同色
        categories.add(Category(
          id: id,
          name: catName,
          colorValue: paletteColorAt(categories.length),
        ));
      }

      // 定制项
      final groups = <MenuOptionGroup>[];
      for (final p in pairs) {
        final groupName = cell(p[0]);
        final rawOptions = cell(p[1]);
        if (groupName.isEmpty || rawOptions.isEmpty) continue;
        final options = rawOptions
            .split('/')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (options.isEmpty) continue;
        groups.add(MenuOptionGroup(name: groupName, options: options));
        optionGroupCount++;
      }

      counter++;
      items.add(MenuItem(
        id: '$idPrefix$counter',
        name: name,
        price: _parsePrice(cell(priceCol)),
        emoji: cell(iconCol),
        categoryId: catIdByName[catName]!,
        options: groups,
      ));
    }

    if (items.isEmpty) {
      throw const MenuImportException('Excel 里没读到任何菜品，请检查列名和内容。');
    }

    return MenuImportResult(
      data: MenuData(categories: categories, items: items),
      categoryCount: categories.length,
      itemCount: items.length,
      optionGroupCount: optionGroupCount,
      warnings: warnings,
    );
  }

  // ---------- 表头识别（中/英/西） ----------

  static bool _isCategoryHeader(String h) =>
      h.contains('种类') ||
      h.contains('类别') ||
      h.contains('分类') ||
      h.contains('category') ||
      h.contains('categoria') ||
      h == 'tipo';

  static bool _isNameHeader(String h) =>
      h.contains('菜品') ||
      h.contains('菜名') ||
      h.contains('名字') ||
      h.contains('名称') ||
      h.contains('name') ||
      h.contains('nombre') ||
      h.contains('producto') ||
      h.contains('dish') ||
      h == 'plato';

  static bool _isPriceHeader(String h) =>
      h.contains('价格') ||
      h.contains('单价') ||
      h.contains('售价') ||
      h.contains('price') ||
      h.contains('precio') ||
      h.contains('importe');

  static bool _isIconHeader(String h) =>
      h.contains('图标') || h.contains('图片') || h.contains('emoji') || h.contains('icon');

  /// 解析价格：支持 `12.5`、`12,50`（西语逗号小数）、带货币符号 `€12,50`。
  static double _parsePrice(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return 0;
    s = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', ''); // 千分位逗号
    }
    return double.tryParse(s) ?? 0;
  }
}
