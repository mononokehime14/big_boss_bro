import 'menu_option_group.dart';

/// 一道菜。价格用 double，用货币符号显示。
///
/// [options] 是该菜的个性化定制项（例如 Size、辣度），点菜时让顾客选。
/// [unit] 是这个菜价的**单位**（Excel 里的「单位」列，例如 份 / 杯 / 公斤）；
/// 空字符串表示没填，界面上就不显示单位。
class MenuItem {
  final String id;
  final String name;
  final double price;
  final String emoji;
  final String categoryId;
  final List<MenuOptionGroup> options;
  final String unit;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.emoji,
    required this.categoryId,
    this.options = const [],
    this.unit = '',
  });

  bool get hasOptions => options.any((g) => !g.isEmpty);

  bool get hasUnit => unit.trim().isNotEmpty;

  /// 「这个菜 + 这些选择」的单价 = 基础价 + 各选中项的加价。
  ///
  /// 例：基础价 0、Size 选 Grande（+185）→ 185；
  /// 基础价 100、加料 +50 → 150。
  ///
  /// 注意：**加料开关**（只有一个选项 / Yes-No，见 `MenuOptionGroup.isToggle`）在单子上
  /// 存的是**组名**（`EXTRA BOBA`、`JARRA`），所以这里也要认组名。
  double unitPriceFor(List<String> selections) {
    var p = price;
    for (final g in options) {
      for (final sel in selections) {
        if (g.options.contains(sel)) {
          p += g.priceOf(sel);
        } else if (g.isToggle && g.name == sel) {
          p += g.togglePrice;
        }
      }
    }
    return p;
  }

  /// 最便宜的搭配（菜单上显示的「起价」）。
  ///
  /// **加料开关**（单选项 / Yes-No）算「**可以不选**」，所以不加进起价里 ——
  /// 这样菜单格子上写的价 = 点菜框里默认显示的价
  /// （默认选择的规则见 `widgets/item_customize_dialog.dart` 的 `_defaultOption`）。
  double get minUnitPrice {
    var p = price;
    for (final g in options) {
      if (g.isEmpty) continue;
      if (g.isToggle) continue; // 加料开关：默认不选
      var min = double.infinity;
      for (var i = 0; i < g.options.length; i++) {
        final v = i < g.prices.length ? g.prices[i] : 0.0;
        if (v < min) min = v;
      }
      if (min.isFinite) p += min;
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'emoji': emoji,
        'categoryId': categoryId,
        'options': options.map((g) => g.toJson()).toList(),
        'unit': unit,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        emoji: (json['emoji'] as String?) ?? '',
        categoryId: json['categoryId'] as String,
        options: (json['options'] as List?)
                ?.map((e) => MenuOptionGroup.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        // 旧数据没有 unit：默认空 = 不显示单位
        unit: (json['unit'] as String?) ?? '',
      );

  MenuItem copyWith({
    String? name,
    double? price,
    String? emoji,
    String? categoryId,
    List<MenuOptionGroup>? options,
    String? unit,
  }) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        emoji: emoji ?? this.emoji,
        categoryId: categoryId ?? this.categoryId,
        options: options ?? this.options,
        unit: unit ?? this.unit,
      );
}
