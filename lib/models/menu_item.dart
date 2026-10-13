import 'menu_option_group.dart';

/// 一道菜。价格用 double，用货币符号显示。
///
/// [options] 是该菜的个性化定制项（例如 Size、辣度），点菜时让顾客选。
/// [unit] 是这个菜价的**单位**（Excel 里的「单位」列，例如 份 / 杯 / 公斤）；
/// 空字符串表示没填，界面上就不显示单位。
/// [minQuantity] 是**最少点几份**（Excel 里的「基础数量」列：套餐 2 份起那种）。
/// [nickName] 是**菜品昵称**（Excel 里的「菜品昵称」列）：店员之间叫的短名。
class MenuItem {
  final String id;
  final String name;
  final double price;
  final String emoji;
  final String categoryId;
  final List<MenuOptionGroup> options;
  final String unit;

  /// **菜品昵称**（Excel 的「菜品昵称」列，例如 `L #1`）—— 员工之间叫得顺口的短名。
  ///
  /// - **点单界面 / 厨师单显示昵称**（员工看的是这个）；
  /// - **顾客小票永远打全名**（[name]）—— 客人看到的必须跟菜单一致；
  /// - 空 = 没有昵称，两边都用全名（[displayName] 会自动回退）。
  final String nickName;

  /// **最少点几份**（Excel 的「基础数量」列；Excel 里没这一列 = 1）。
  ///
  /// 点菜弹窗里**数量从它开始**（可以往上加，但不能减到比它少）；
  /// 长按快捷加一份也是加这么多。
  final int minQuantity;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.emoji,
    required this.categoryId,
    this.options = const [],
    this.unit = '',
    this.nickName = '',
    this.minQuantity = 1,
  });

  /// 界面上显示的名字：**有昵称就用昵称，没有就用全名**。
  String get displayName =>
      nickName.trim().isEmpty ? name : nickName.trim();

  bool get hasOptions => options.any((g) => !g.isEmpty);

  bool get hasUnit => unit.trim().isNotEmpty;

  /// 是不是"几份起"的菜（2 份起这种才需要提示）。
  bool get hasMinQuantity => minQuantity > 1;

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
        'nickName': nickName,
        'minQuantity': minQuantity,
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
        // 旧数据没有昵称：默认空 = 昵称即全名
        nickName: (json['nickName'] as String?) ?? '',
        // 旧数据没有 minQuantity：默认 1 = 一份起
        minQuantity: (json['minQuantity'] as num?)?.toInt() ?? 1,
      );

  MenuItem copyWith({
    String? name,
    double? price,
    String? emoji,
    String? categoryId,
    List<MenuOptionGroup>? options,
    String? unit,
    String? nickName,
    int? minQuantity,
  }) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        emoji: emoji ?? this.emoji,
        categoryId: categoryId ?? this.categoryId,
        options: options ?? this.options,
        unit: unit ?? this.unit,
        nickName: nickName ?? this.nickName,
        minQuantity: minQuantity ?? this.minQuantity,
      );
}
