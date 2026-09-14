import 'menu_option_group.dart';

/// 一道菜。价格用 double，用货币符号显示。
///
/// [options] 是该菜的个性化定制项（例如 Size、辣度），点菜时让顾客选。
class MenuItem {
  final String id;
  final String name;
  final double price;
  final String emoji;
  final String categoryId;
  final List<MenuOptionGroup> options;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.emoji,
    required this.categoryId,
    this.options = const [],
  });

  bool get hasOptions => options.any((g) => !g.isEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'emoji': emoji,
        'categoryId': categoryId,
        'options': options.map((g) => g.toJson()).toList(),
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
      );

  MenuItem copyWith({
    String? name,
    double? price,
    String? emoji,
    String? categoryId,
    List<MenuOptionGroup>? options,
  }) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        emoji: emoji ?? this.emoji,
        categoryId: categoryId ?? this.categoryId,
        options: options ?? this.options,
      );
}
