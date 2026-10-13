import '../data/menu_store.dart';
import '../l10n/app_strings.dart';
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

/// 一个定制项占的列：名字列、选项列、价格列（价格列可能没有）。
class _GroupCols {
  final int nameCol;
  final int optionsCol;
  final int? pricesCol;

  const _GroupCols(this.nameCol, this.optionsCol, this.pricesCol);
}

/// 表头认出来的「列布局」。
class _Layout {
  final int catCol;
  final int nameCol;
  final int? priceCol;
  final int? unitCol;
  final int? iconCol;

  /// 「**菜品昵称**」列（可选）。
  ///
  /// **必须认出来并"占住"这一列**：它的表头叫「菜品昵称」，里面带「菜品」两个字，
  /// 会被「菜名」规则认走；而且它右边紧跟着定制项 —— 不占住的话，这一列会被当成
  /// 一组定制项的**名字列**，把「定制1选项」当成它的选项（真实踩过：整张菜单全歪）。
  final int? nickCol;

  /// 「基础数量」列（最少点几份）。**必须认出来并"占住"这一列**，
  /// 否则它会被当成下一组定制项的开始（真实踩过：
  /// 加了「基础数量」列之后，Verdura Cantones 莫名多出一组定制项）。
  final int? quantityCol;

  final List<_GroupCols> groups;

  const _Layout({
    required this.catCol,
    required this.nameCol,
    this.priceCol,
    this.unitCol,
    this.iconCol,
    this.nickCol,
    this.quantityCol,
    this.groups = const [],
  });
}

/// 把菜单 Excel 解析成菜单数据（**列数和列顺序都不写死**）。
///
/// 认列的规则（全部按**表头名字**认，不看第几列）：
/// - 分类列：`种类` / `类别` / `分类` / `category` / `categoria`；
/// - 菜名列：`菜品名字` / `菜名` / `名称` / `name` / `nombre` / `producto`；
/// - **基础价格**列：`基础价格` / `价格` / `单价` / `price` / `precio`；
/// - **菜品昵称**列（可选）：`菜品昵称` / `昵称` / `简称` / `nickname` / `apodo`
///   → 写进 `MenuItem.nickName`：**点单界面 / 厨师单显示昵称，顾客小票打全名**；
///   空 = 昵称即全名；
/// - **基础数量**列（可选）：`基础数量` / `起订数量` / `最少` / `minqty` / `cantidad`…
///   → 写进 `MenuItem.minQuantity`：点菜弹窗里**数量从它开始**（例：套餐 2 份起）；
/// - 单位列（可选）：`单位` / `unit` / `unidad`；
/// - 图标列（可选）：`图标` / `emoji` / `icon`；
/// - **定制项**列：`个性化定制项1`、`定制项2`、`定制项3`、`Size`、`JARRA`…（**有几个算几个**，
///   不限于 2 个 —— 现在样例表里就有 3 组）。每个定制项右边**紧跟着它的「选项」和
///   「选项价格」**两列：
///   ```
///   | 种类 | 菜品名字 | 菜品昵称 | 基础价格 | 基础数量 | 个性化定制项1 | 定制1选项 | 定制1选项价格 | 定制项2 | 定制2选项 | 定制2选项价格 | … |
///   ```
///   选项用 `/` 分隔，价格也按 `/` 一一对应（`Mediano/Grande` + `150/200`）。
///
/// ⚠️ 关键列（分类 / 菜名 / **昵称** / 价格 / 数量 / 单位 / 图标）认出来之后会
/// **标记为已占用**，剩下的列才按"三列一组"切分定制项 —— 所以**新加一列关键字段
/// 不会把定制项搞乱**（昵称列踩过这个坑：它右边就是定制项）。
///
/// 容错：
/// - **定制项名字那格留空**（同一段里只写一次）→ 沿用**上面最近一次**写过的名字；
/// - **基础价格留空**（价格全靠选项价格时）→ 记 0，单价 = 0 + 所选加价；
/// - 「选项价格」列可以没有 → 这种定制项不加价。
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

    // 1) 找表头行：**认得的关键列最多**的那一行（前 40 行里找）
    final headerIdx = _findHeaderRow(rows);
    if (headerIdx < 0) {
      throw const MenuImportException('Excel 里没读到内容（表头都没有）。');
    }
    final header = rows[headerIdx];

    // 2) 认列
    final layout = _readLayout(rows, headerIdx, header, warnings);

    // 3) 逐行读菜品
    final categories = <Category>[];
    final catIdByName = <String, String>{};
    final items = <MenuItem>[];
    // 每个定制项「名字」的延续值：这一格留空就沿用上面最近写过的名字
    final lastName = List<String>.filled(layout.groups.length, '');
    var optionGroupCount = 0;
    var counter = 0;
    var lastCategory = '';
    var usedDefaultGroupName = false;

    for (var r = headerIdx + 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int? i) =>
          (i != null && i >= 0 && i < row.length) ? row[i].trim() : '';

      final rawCat = cell(layout.catCol);
      final name = cell(layout.nameCol);
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

      // 定制项（名字 + 选项 [+ 每个选项的价格]）
      final groups = <MenuOptionGroup>[];
      for (var gi = 0; gi < layout.groups.length; gi++) {
        final g = layout.groups[gi];
        final rawGroupName = cell(g.nameCol);
        if (rawGroupName.isNotEmpty) lastName[gi] = rawGroupName; // 记住给下面几行用

        final rawOptions = cell(g.optionsCol);
        if (rawOptions.isEmpty) continue;
        final options = rawOptions
            .split('/')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (options.isEmpty) continue;

        var groupName = rawGroupName.isNotEmpty ? rawGroupName : lastName[gi];
        if (groupName.isEmpty) {
          // 整列都没写过名字：给个通用名字，别让这组选项丢掉
          groupName = L10n.t('menu.optionGroup.default');
          usedDefaultGroupName = true;
        }
        groups.add(MenuOptionGroup(
          name: groupName,
          options: options,
          prices: _parsePrices(cell(g.pricesCol), options.length),
        ));
        optionGroupCount++;
      }

      counter++;
      items.add(MenuItem(
        id: '$idPrefix$counter',
        name: name,
        price: _parsePrice(cell(layout.priceCol)),
        emoji: cell(layout.iconCol),
        categoryId: catIdByName[catName]!,
        options: groups,
        // 单位（Excel 的「单位」列）：例如 份 / 杯 / 公斤；没这列就是空
        unit: cell(layout.unitCol),
        // 菜品昵称（Excel 的「菜品昵称」列）：点单界面 / 厨师单显示它；空 = 用全名
        nickName: cell(layout.nickCol),
        // 基础数量（Excel 的「基础数量」列）：最少点几份；没这列就是 1
        minQuantity: _parseQuantity(cell(layout.quantityCol)),
      ));
    }

    if (items.isEmpty) {
      throw const MenuImportException('Excel 里没读到任何菜品，请检查列名和内容。');
    }
    if (usedDefaultGroupName) {
      warnings.add('有些定制项没有写名字（那一格是空的），已用'
          '「${L10n.t('menu.optionGroup.default')}」当名字；'
          '在 Excel 里给它们写上名字（例如 Size / JARRA）更清楚。');
    }

    return MenuImportResult(
      data: MenuData(categories: categories, items: items),
      categoryCount: categories.length,
      itemCount: items.length,
      optionGroupCount: optionGroupCount,
      warnings: warnings,
    );
  }

  // -------------------------------------------------------------------------
  // 认表头 / 认列
  // -------------------------------------------------------------------------

  /// 找表头行：在前 40 行里挑「认得的关键列最多」的那一行（至少 2 个）。
  /// 找不到就退回「第一条非空单元格 >= 2 的行」（老行为）。
  static int _findHeaderRow(List<List<String>> rows) {
    var best = -1;
    var bestScore = 0;
    final limit = rows.length < 40 ? rows.length : 40;
    for (var i = 0; i < limit; i++) {
      var score = 0;
      for (final cell in rows[i]) {
        final h = cell.trim().toLowerCase();
        if (h.isEmpty) continue;
        if (_isCategoryHeader(h) ||
            _isNameHeader(h) ||
            _isPriceLike(h) ||
            _isUnitHeader(h) ||
            _isIconHeader(h) ||
            _isNickHeader(h) ||
            _isQuantityHeader(h)) {
          score++;
        }
      }
      if (score >= 2 && score > bestScore) {
        best = i;
        bestScore = score;
      }
    }
    if (best >= 0) return best;

    for (var i = 0; i < rows.length; i++) {
      if (rows[i].where((c) => c.trim().isNotEmpty).length >= 2) return i;
    }
    return -1;
  }

  /// 认列：先按名字认关键列（分类 / 菜名 / 基础价格 / 单位 / 图标），
  /// 剩下的列**按「定制项 → 选项 → 选项价格」三列一组**依次切分。
  static _Layout _readLayout(
    List<List<String>> rows,
    int headerIdx,
    List<String> header,
    List<String> warnings,
  ) {
    final width = header.length;
    String h(int i) =>
        (i >= 0 && i < width) ? header[i].trim().toLowerCase() : '';

    final claimed = <int>{};
    int? catCol, nameCol, priceCol, unitCol, iconCol, quantityCol, nickCol;

    for (var c = 0; c < width; c++) {
      final x = h(c);
      if (x.isEmpty) continue;
      if (catCol == null && _isCategoryHeader(x)) {
        catCol = c;
        claimed.add(c);
        continue;
      }
      // ⚠️ 昵称要在「菜名」**之前**认：`菜品昵称` 里也有「菜品」两个字，
      //    否则会被菜名规则认走（菜名已经认过第一列就没关系，但顺序不能反）
      if (nickCol == null && _isNickHeader(x)) {
        nickCol = c;
        claimed.add(c);
        continue;
      }
      if (nameCol == null && _isNameHeader(x)) {
        nameCol = c;
        claimed.add(c);
        continue;
      }
      if (unitCol == null && _isUnitHeader(x)) {
        unitCol = c;
        claimed.add(c);
        continue;
      }
      if (iconCol == null && _isIconHeader(x)) {
        iconCol = c;
        claimed.add(c);
        continue;
      }
      // 基础数量必须在「定制项分组」之前认掉 —— 否则这一列会被当成
      // 下一组定制项的名字列，把后面的选项全带歪（真实踩过）
      if (quantityCol == null && _isQuantityHeader(x)) {
        quantityCol = c;
        claimed.add(c);
        continue;
      }
      // 基础价格：价格类表头，而且**不是**某个「选项」右边那一列
      // （「定制1选项价格」也是价格类表头，但它属于定制项 1，不能当基础价）
      if (priceCol == null && _isPriceLike(x) && !_isOptionsHeader(h(c - 1))) {
        priceCol = c;
        claimed.add(c);
        continue;
      }
    }

    // 剩下的列：三列一组（定制项、选项、选项价格）
    final groups = <_GroupCols>[];
    var c = 0;
    while (c < width) {
      if (claimed.contains(c)) {
        c++;
        continue;
      }
      final nameColIdx = c;
      // 「右边一定跟着选项」：取右边第一个还没被认走的列
      var optCol = -1;
      for (var k = c + 1; k < width; k++) {
        if (claimed.contains(k)) continue;
        optCol = k;
        break;
      }
      if (optCol < 0) {
        // 光有名字列、右边没东西了：忽略
        break;
      }
      // 选项右边那列：是价格列就认；表头空着但数据是数字也认（很多表懒得写表头）
      int? pricesCol;
      final after = optCol + 1;
      if (after < width && !claimed.contains(after)) {
        final ah = h(after);
        if (_isPriceLike(ah) || (ah.isEmpty && _looksNumeric(rows, headerIdx, after))) {
          pricesCol = after;
        }
      }
      groups.add(_GroupCols(nameColIdx, optCol, pricesCol));
      claimed.add(nameColIdx);
      claimed.add(optCol);
      if (pricesCol != null) claimed.add(pricesCol);
      c = (pricesCol ?? optCol) + 1;
    }

    // 兜底：分类/菜名没认出来就按前两列
    catCol ??= 0;
    nameCol ??= (catCol == 0) ? 1 : 0;

    // 兜底：没找到「基础价格」列 → 在定制项之前找一个「看起来是数字」的列当基础价
    if (priceCol == null) {
      final firstGroupCol = groups.isEmpty ? width : groups.first.nameCol;
      for (var k = 0; k < firstGroupCol; k++) {
        if (claimed.contains(k) || k == catCol || k == nameCol) continue;
        if (_looksNumeric(rows, headerIdx, k)) {
          priceCol = k;
          claimed.add(k);
          warnings.add('没有「基础价格」表头，已按第 ${k + 1} 列的数字当基础价。');
          break;
        }
      }
    }
    if (priceCol == null) {
      warnings.add('没有找到「基础价格」列 → 菜品价格先按 0 处理；'
          '可以在 Excel 里加一列「基础价格」，或在 App 的「菜品管理」里逐个改。');
    }

    return _Layout(
      catCol: catCol,
      nameCol: nameCol,
      priceCol: priceCol,
      unitCol: unitCol,
      iconCol: iconCol,
      nickCol: nickCol,
      quantityCol: quantityCol,
      groups: groups,
    );
  }

  /// 这一列（表头下面）的数据是不是基本都像数字/数字列表（`150/200` 也算）。
  ///
  /// 用途：表头没写「价格」时判断这列是不是价格列 —— 有数据才敢认。
  static bool _looksNumeric(List<List<String>> rows, int headerIdx, int col) {
    var seen = 0;
    var numeric = 0;
    for (var r = headerIdx + 1; r < rows.length && seen < 20; r++) {
      final row = rows[r];
      if (col >= row.length) continue;
      final v = row[col].trim();
      if (v.isEmpty) continue;
      seen++;
      final parts = v.split('/');
      if (parts.every((p) => _parsePrice(p) > 0 || p.trim() == '0')) numeric++;
    }
    return seen > 0 && numeric == seen;
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

  /// 价格类表头（含「定制1选项价格」这种）。基础价列的判定用它。
  static bool _isPriceLike(String h) =>
      _isPriceHeader(h) || h.contains('加价') || h.contains('monto');

  /// 「选项」类表头：`定制1选项` / `选项` / `opciones` / `options` / `valor`。
  static bool _isOptionsHeader(String h) =>
      (h.contains('选项') && !h.contains('价格')) ||
      h.contains('opcion') ||
      h.contains('opción') ||
      h.contains('option') ||
      h.contains('valor') ||
      h.contains('values');

  static bool _isIconHeader(String h) =>
      h.contains('图标') || h.contains('图片') || h.contains('emoji') || h.contains('icon');

  /// 「**菜品昵称**」列（可选）：`菜品昵称` / `昵称` / `简称` / `别名` / `nickname` / `apodo`。
  ///
  /// ⚠️ 认它的顺序要在「菜名」**之前** —— 「菜品昵称」里也含「菜品」，
  /// 而且它右边紧跟着定制项，认漏了整张菜单的定制项都会歪。
  static bool _isNickHeader(String h) =>
      h.contains('昵称') ||
      h.contains('简称') ||
      h.contains('别名') ||
      h.contains('nick') ||
      h.contains('apodo') ||
      h.contains('alias') ||
      h.contains('sobrenombre');

  /// 「单位」列：`单位` / `计量单位` / `unit` / `unidad`。
  /// 例：份、杯、碟、公斤 —— 会显示在菜单格子和厨房单的数量后面。
  static bool _isUnitHeader(String h) =>
      h.contains('单位') ||
      h.contains('计量') ||
      h == 'unit' ||
      h.contains('unidad') ||
      h.contains('medida');

  /// 「**基础数量**」列（最少点几份）：`基础数量` / `起订` / `最少` / `minqty` / `cantidad`…
  ///
  /// 注意**不能**把「定制1选项」之类的列误认成数量列 → 先排掉选项/价格类表头。
  static bool _isQuantityHeader(String h) {
    if (_isOptionsHeader(h) || _isPriceLike(h)) return false;
    return h.contains('基础数量') ||
        h.contains('起订') ||
        h.contains('最少') ||
        h.contains('基数') ||
        h.contains('数量') ||
        h.contains('qty') ||
        h.contains('quantity') ||
        h.contains('cantidad');
  }

  /// 解析「基础数量」：`2` → 2；`2.0` / `2 份` / 空 → 数字部分。
  /// **至少 1**，最大 99（防止表里写了奇怪的东西把数量顶到天上）。
  static int _parseQuantity(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 1;
    final n = int.tryParse(digits) ?? 1;
    if (n < 1) return 1;
    return n > 99 ? 99 : n;
  }

  /// 解析「每个选项的价格」：`140/185` → [140, 185]。
  /// 长度按 [count]（选项个数）对齐，缺的补 0。
  static List<double> _parsePrices(String raw, int count) {
    if (raw.trim().isEmpty) return const [];
    final parts = raw.split('/');
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      out.add(i < parts.length ? _parsePrice(parts[i]) : 0);
    }
    return out;
  }

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
