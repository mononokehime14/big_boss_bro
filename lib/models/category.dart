/// 一个菜品分类（如：热菜、主食、饮料）。
///
/// [colorValue] 是这个分类的底色（ARGB 整数）。0 表示“没设过”，
/// 界面会按分类顺序从调色板里自动取色（见 `utils/category_colors.dart`）。
class Category {
  final String id;
  final String name;
  final String emoji;
  final int colorValue;

  const Category({
    required this.id,
    required this.name,
    this.emoji = '',
    this.colorValue = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: (json['emoji'] as String?) ?? '',
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0,
      );

  Category copyWith({
    String? id,
    String? name,
    String? emoji,
    int? colorValue,
  }) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
      );
}
