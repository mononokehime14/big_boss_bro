import 'menu_item.dart';

/// 购物车里的一行：某道菜 + 份数 + 所选的定制选项 + **特别备注**（可以好几条）。
///
/// 同一道菜**选项/备注的组合不同算不同的行**（例如“大份”和“中份”分开显示）。
class CartItem {
  final MenuItem menuItem;

  /// 份数（点菜对话框里默认 1，可以加减或直接输）。
  int quantity;

  /// 所选的定制项值，例如 ['Grande'] 或 ['中辣']。
  final List<String> selections;

  /// **特别备注**：可以填好几条（在点菜对话框里一条一条存进去）。
  final List<String> notes;

  CartItem({
    required this.menuItem,
    this.quantity = 1,
    List<String>? selections,
    List<String>? notes,
  })  : selections = selections ?? <String>[],
        notes = notes ?? <String>[];

  /// 所有备注拼成一行（显示 / 打印用）。
  String get note => notes.join(' · ');

  /// 购物车里的唯一键：同菜 + 同选项 + 同备注 才算同一行。
  ///
  /// 备注之间用 `\u0001` 分隔：否则「一条备注 a/b」和「两条备注 a、b」会撞成同一行。
  String get key =>
      '${menuItem.id}|${selections.join('/')}|${notes.join('\u0001')}';

  /// 单价 = 基础价 + 所选项的加价（见 `MenuItem.unitPriceFor`）。
  double get unitPrice => menuItem.unitPriceFor(selections);

  double get lineTotal => unitPrice * quantity;

  /// 选项 + 备注的简短描述（显示在购物车 / 小票里）。
  String get detail {
    final parts = <String>[];
    if (selections.isNotEmpty) parts.add(selections.join(' / '));
    if (note.trim().isNotEmpty) parts.add(note.trim());
    return parts.join(' · ');
  }
}
