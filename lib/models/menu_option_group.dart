/// 一个「个性化定制项」，例如 `Size: [Mediano, Grande]` 或 `辣度: [不辣, 微辣, 中辣]`。
///
/// 从 Excel 里读：定制项名在左列，选项在右列、用 `/` 分隔。
class MenuOptionGroup {
  final String name;
  final List<String> options;

  const MenuOptionGroup({required this.name, required this.options});

  bool get isEmpty => name.trim().isEmpty || options.isEmpty;

  MenuOptionGroup copyWith({String? name, List<String>? options}) =>
      MenuOptionGroup(
        name: name ?? this.name,
        options: options ?? this.options,
      );

  Map<String, dynamic> toJson() => {'name': name, 'options': options};

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) =>
      MenuOptionGroup(
        name: json['name'] as String,
        options: (json['options'] as List).map((e) => e.toString()).toList(),
      );
}
