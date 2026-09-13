/// 一个菜品分类（如：热菜、主食、饮料）。
class Category {
  final String id;
  final String name;
  final String emoji;

  const Category({
    required this.id,
    required this.name,
    required this.emoji,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji};

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
      );

  Category copyWith({String? id, String? name, String? emoji}) => Category(
        id: id ?? this.id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
      );
}
