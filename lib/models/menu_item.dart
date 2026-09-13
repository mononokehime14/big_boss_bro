/// 一道菜。价格用 double（元），用货币符号显示。
class MenuItem {
  final String id;
  final String name;
  final double price;
  final String emoji;
  final String categoryId;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.emoji,
    required this.categoryId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'emoji': emoji,
        'categoryId': categoryId,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        emoji: json['emoji'] as String,
        categoryId: json['categoryId'] as String,
      );

  MenuItem copyWith({String? name, double? price, String? emoji, String? categoryId}) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        emoji: emoji ?? this.emoji,
        categoryId: categoryId ?? this.categoryId,
      );
}
