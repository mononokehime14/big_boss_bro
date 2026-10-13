import '../models/category.dart';
import '../models/menu_item.dart';

/// 点单区（种类 / 菜品）的排序方式。
enum MenuSort {
  /// **默认：本机记住的顺序**。
  ///
  /// 一开始就是菜单原本的顺序（Excel 导入的）；用户在点单页**长按拖动格子**之后就按
  /// 拖出来的顺序 —— 顺序存在 `Settings.menuOrder`，**只在这台设备上有用，不上云**
  /// （属于"这台设备怎么看菜单"的偏好）。规则见 [sortByCustomOrder]。
  natural('default'),

  /// 按名字的首字母 A→Z（大小写不敏感）。
  ///
  /// 注意：**中文名按 Unicode 码位排，不是拼音**。菜单是西语/英语名（例如
  /// `ARROZ CON CAMARON`）时就是标准的字母顺序；要按拼音排需要额外加拼音表。
  name('name'),

  /// 按**卖出的份数**（多的在前）；份数一样时按名字排。
  /// 份数在**结账确认**时累加，见 `PosController.closeOrder`。
  popular('popular');

  final String id;
  const MenuSort(this.id);

  /// 认不出的 id（例如老版本存过的 `'custom'`）**一律当「默认」** ——
  /// 默认排序用的就是用户拖出来的顺序，所以老设备切过来是无缝的。
  static MenuSort fromId(String? id) => MenuSort.values.firstWhere(
        (e) => e.id == id,
        orElse: () => MenuSort.natural,
      );
}

/// 排序用的名字键：去空白 + 转小写（`an` 和 `An` 排在一起）。
String menuSortKey(String name) => name.trim().toLowerCase();

/// 按 [mode] 排**种类**；[popularity] 是「分类 id → 卖出的份数」。
///
/// [order] 是**本机记下来的顺序表**（`Settings.menuOrder`），只在 [MenuSort.natural]
/// （默认）时用：**空表 = 菜单原本的顺序**。
List<Category> sortCategories(
  List<Category> categories,
  MenuSort mode,
  Map<String, int> popularity, {
  List<String> order = const [],
}) {
  final out = List<Category>.of(categories);
  switch (mode) {
    case MenuSort.natural:
      return sortByCustomOrder(out, (c) => c.id, order);
    case MenuSort.name:
      out.sort((a, b) => menuSortKey(a.name).compareTo(menuSortKey(b.name)));
      return out;
    case MenuSort.popular:
      out.sort((a, b) {
        final byCount =
            (popularity[b.id] ?? 0).compareTo(popularity[a.id] ?? 0);
        if (byCount != 0) return byCount;
        return menuSortKey(a.name).compareTo(menuSortKey(b.name));
      });
      return out;
  }
}

/// 按 [mode] 排**菜品**；[popularity] 是「菜品 id → 卖出的份数」。
///
/// [order] 是**本机记下来的顺序表**（`Settings.menuOrder`），只在 [MenuSort.natural]
/// （默认）时用：**空表 = 菜单原本的顺序**。
List<MenuItem> sortMenuItems(
  List<MenuItem> items,
  MenuSort mode,
  Map<String, int> popularity, {
  List<String> order = const [],
}) {
  final out = List<MenuItem>.of(items);
  switch (mode) {
    case MenuSort.natural:
      return sortByCustomOrder(out, (m) => m.id, order);
    case MenuSort.name:
      out.sort((a, b) => menuSortKey(a.name).compareTo(menuSortKey(b.name)));
      return out;
    case MenuSort.popular:
      out.sort((a, b) {
        final byCount =
            (popularity[b.id] ?? 0).compareTo(popularity[a.id] ?? 0);
        if (byCount != 0) return byCount;
        return menuSortKey(a.name).compareTo(menuSortKey(b.name));
      });
      return out;
  }
}

/// **本机顺序**（默认排序）用：把 [items] 按 [order] 里的先后排好。
///
/// - 在 [order] 里的：按它在表里的下标排；
/// - **不在里面的**（新导入的菜、还没拖过的）：排到最后，并保持它们自己的先后。
///
/// 为什么不用「表里没有就当 0」：Dart 的 `List.sort` **不稳定**，
/// 那样写同样名次的会乱跳。这里给"没排过的"一个确定的名次（`order.length + 原下标`），
/// 结果就永远是确定的。
List<T> sortByCustomOrder<T>(
  List<T> items,
  String Function(T) idOf,
  List<String> order,
) {
  final at = <String, int>{};
  for (var i = 0; i < order.length; i++) {
    at[order[i]] = i;
  }
  final keyed = <MapEntry<int, T>>[];
  for (var i = 0; i < items.length; i++) {
    keyed.add(MapEntry(at[idOf(items[i])] ?? (order.length + i), items[i]));
  }
  keyed.sort((a, b) => a.key.compareTo(b.key));
  return keyed.map((e) => e.value).toList();
}

/// **拖动之后**这一组的新顺序：把 [movedId] 挪到 [targetId] 原来的位置。
///
/// 例：`[a, b, c]` 把 `c` 拖到 `a` 上 → `[c, a, b]`；
/// `movedId` 不在表里 / `targetId` 找不到 → 尽力而为（找不到就放到最后）。
List<String> moveBefore(List<String> ids, String movedId, String targetId) {
  if (movedId == targetId) return List<String>.of(ids);
  final out = List<String>.of(ids);
  out.remove(movedId); // 不在表里也没关系：下面照样把它插到目标前面
  final at = out.indexOf(targetId);
  out.insert(at < 0 ? out.length : at, movedId);
  return out;
}

/// 把「拖过的那一组」的新顺序写回**全局顺序表**。
///
/// 为什么不是整表重写：全局表里同时装着**种类和菜品的 id**，而屏幕上一次只看得到
/// **一组**（所有种类、或某个种类下的菜）。排序只在组内比先后，所以把这一组整个挪到
/// 表尾（组内先后保留）就够，其它组的 id 原样不动。
List<String> applyVisibleOrder(
  List<String> stored,
  List<String> visibleInNewOrder,
) {
  final visible = visibleInNewOrder.toSet();
  return <String>[
    ...stored.where((id) => !visible.contains(id)),
    ...visibleInNewOrder,
  ];
}

// ---------------------------------------------------------------------------
// 桌号（或其他名字够乱的列表）的**自然顺序**
// ---------------------------------------------------------------------------

/// **自然顺序**比较：数字段按数值比、文字段按字母比（大小写不敏感）。
///
/// 用它排桌号，出来的就是 `1 2 9 10 A B C S-A S-B` 这种人类顺序
/// （直接按字符串排会变成 `1 10 2 …`，数字大的反而在前）。
///
/// 数字排在字母前面：`'1'` (0x31) 比 `'a'` (0x61) 小，天然就满足了。
int naturalCompare(String a, String b) {
  final ra = _runs(a);
  final rb = _runs(b);
  final n = ra.length < rb.length ? ra.length : rb.length;
  for (var i = 0; i < n; i++) {
    final x = ra[i];
    final y = rb[i];
    if (_isDigits(x) && _isDigits(y)) {
      final c = _compareDigits(x, y);
      if (c != 0) return c;
    } else {
      final c = x.toLowerCase().compareTo(y.toLowerCase());
      if (c != 0) return c;
    }
  }
  return ra.length.compareTo(rb.length);
}

/// 桌号列表按自然顺序排好（不改原来的列表）。
List<String> sortedTables(Iterable<String> tables) =>
    tables.toList()..sort(naturalCompare);

/// 把名字切成「数字段 / 非数字段」：`S-A12` → `[S-, A, 12]`。
List<String> _runs(String s) => RegExp(r'\d+|\D+')
    .allMatches(s.trim())
    .map((m) => m.group(0)!)
    .where((e) => e.isNotEmpty)
    .toList();

bool _isDigits(String s) => RegExp(r'^\d+$').hasMatch(s);

/// 两个数字段比大小：先去掉前导 0，再比长度、最后按字符比（不会溢出）。
int _compareDigits(String a, String b) {
  final x = a.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final y = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (x.length != y.length) return x.length - y.length;
  return x.compareTo(y);
}
