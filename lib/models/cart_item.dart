import 'menu_item.dart';

/// 购物车里的一行：某道菜 + 份数 + 所选的定制选项 + 「其他备注」。
///
/// 同一道菜**不同选项/备注的组合算不同的行**（例如“大份”和“中份”分开显示）。
class CartItem {
  final MenuItem menuItem;
  int quantity;

  /// 所选的定制项值，例如 ['Grande'] 或 ['中辣']。
  final List<String> selections;

  /// 「其他备注」，例如“米饭替换成面条”。
  final String note;

  CartItem({
    required this.menuItem,
    this.quantity = 1,
    List<String>? selections,
    this.note = '',
  }) : selections = selections ?? <String>[];

  /// 购物车里的唯一键：同菜 + 同选项 + 同备注 才算同一行。
  String get key => '${menuItem.id}|${selections.join('/')}|$note';

  double get lineTotal => menuItem.price * quantity;

  /// 选项 + 备注的简短描述（显示在购物车 / 小票里）。
  String get detail {
    final parts = <String>[];
    if (selections.isNotEmpty) parts.add(selections.join(' / '));
    if (note.trim().isNotEmpty) parts.add(note.trim());
    return parts.join(' · ');
  }
}
