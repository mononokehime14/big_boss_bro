import 'menu_item.dart';

/// 购物车里的一行：某道菜 + 份数。
class CartItem {
  final MenuItem menuItem;
  int quantity;

  CartItem({required this.menuItem, this.quantity = 1});

  double get lineTotal => menuItem.price * quantity;
}
