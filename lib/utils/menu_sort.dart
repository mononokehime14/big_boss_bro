import '../models/category.dart';
import '../models/menu_item.dart';

/// 点单区（种类 / 菜品）的排序方式。
enum MenuSort {
  /// 菜单原本的顺序（Excel 导入的顺序）—— 默认，什么都不动。
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

  static MenuSort fromId(String? id) => MenuSort.values.firstWhere(
        (e) => e.id == id,
        orElse: () => MenuSort.natural,
      );
}

/// 排序用的名字键：去空白 + 转小写（`an` 和 `An` 排在一起）。
String menuSortKey(String name) => name.trim().toLowerCase();

/// 按 [mode] 排**种类**；[popularity] 是「分类 id → 卖出的份数」。
List<Category> sortCategories(
  List<Category> categories,
  MenuSort mode,
  Map<String, int> popularity,
) {
  final out = List<Category>.of(categories);
  switch (mode) {
    case MenuSort.natural:
      return out;
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
List<MenuItem> sortMenuItems(
  List<MenuItem> items,
  MenuSort mode,
  Map<String, int> popularity,
) {
  final out = List<MenuItem>.of(items);
  switch (mode) {
    case MenuSort.natural:
      return out;
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
