/// 一个「个性化定制项」，例如 `Size: [Mediano, Grande]` 或 `辣度: [不辣, 微辣, 中辣]`。
///
/// 从 Excel 里读：定制项名一列，选项一列（用 `/` 分隔），
/// **后面还可以跟一列「每个选项的价格」**（同样用 `/` 分隔，和选项一一对应）。
/// 例如 `Size | Mediano/Grande | 140/185`。
class MenuOptionGroup {
  final String name;
  final List<String> options;

  /// 与 [options] 一一对应的加价（没有就是 0）。
  /// 例如 `[140, 185]`：选 Mediano 加 140，选 Grande 加 185。
  final List<double> prices;

  const MenuOptionGroup({
    required this.name,
    required this.options,
    this.prices = const [],
  });

  bool get isEmpty => name.trim().isEmpty || options.isEmpty;

  /// 这个定制项是不是「**加料开关**」：
  /// - **只有一个选项**（Excel 里那一格没写 `/`），例如 `EXTRA BOBA | Yes | 25`；
  /// - 或者正好是一对 **Yes/No**（`JARRA | Yes/No | 125/0`）。
  ///
  /// 这种组的语义是「**要不要加这个？**」，所以：
  /// - 点菜框里**默认不选**（不加钱；菜单格子上显示的起价 = 基础价）；
  /// - 选了之后，订单/小票上写的是**组名**（`EXTRA BOBA` / `JARRA`）——
  ///   写「Yes」在票上谁也看不懂；
  /// - 加的钱 = 组里**最贵**的那个价（通常就是 Yes 那个）。
  bool get isToggle {
    if (options.length == 1) return true;
    if (options.length != 2) return false;
    return options.every(_isYesNoWord);
  }

  static const Set<String> _yesNoWords = {
    'yes', 'no', 'si', 'sí', 'y', 'n', 's', 'ok',
    '是', '否', '要', '不要', '加', '不加',
  };

  static bool _isYesNoWord(String v) =>
      _yesNoWords.contains(v.trim().toLowerCase());

  /// 「加料开关」打开时加的钱（组里最贵的那个价）。
  double get togglePrice {
    if (prices.isEmpty) return 0;
    return prices.reduce((a, b) => a > b ? a : b);
  }

  /// 某个选项的加价（找不到就是 0）。
  double priceOf(String option) {
    final i = options.indexOf(option);
    if (i < 0 || i >= prices.length) return 0;
    return prices[i];
  }

  bool get hasPrices => prices.any((p) => p != 0);

  MenuOptionGroup copyWith({
    String? name,
    List<String>? options,
    List<double>? prices,
  }) =>
      MenuOptionGroup(
        name: name ?? this.name,
        options: options ?? this.options,
        prices: prices ?? this.prices,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'options': options, 'prices': prices};

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) =>
      MenuOptionGroup(
        name: json['name'] as String,
        options: (json['options'] as List).map((e) => e.toString()).toList(),
        prices: (json['prices'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
      );
}
