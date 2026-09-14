import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../data/menu_store.dart';
import '../data/order_store.dart';
import '../data/sample_menu.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/order.dart';

/// 核心状态：购物车、点单、结账、已结订单、菜单（分类+菜品）。
///
/// 用 ChangeNotifier，界面用 Provider 监听，订单/购物车/菜单一变就自动刷新。
/// - 已结订单通过 [OrderStore] 持久化（重启不丢）。
/// - 菜单（分类+菜品）通过 [MenuStore] 持久化，可在设置里自定义。
class PosController extends ChangeNotifier {
  /// 所有订单（含“进行中”和“已结单”）。
  final List<Order> _orders = [];

  /// 进行中的单（已下单、还没结账）。
  List<Order> get inProgressOrders =>
      _orders.where((o) => o.status == OrderStatus.inProgress).toList();

  /// 已结单。
  List<Order> get completedOrders =>
      _orders.where((o) => o.status == OrderStatus.completed).toList();

  List<Category> _categories;
  List<MenuItem> _menu;

  final OrderStore _orderStore;
  final MenuStore _menuStore;

  // 用来生成单号。
  int _orderCounter = 1;

  List<Category> get categories => _categories;
  List<MenuItem> get menu => _menu;

  PosController({
    List<Category>? categories,
    List<MenuItem>? menu,
    OrderStore? orderStore,
    MenuStore? menuStore,
  })  : _categories = categories ?? List.of(sampleCategories),
        _menu = menu ?? List.of(sampleMenu),
        _orderStore = orderStore ?? OrderStore(),
        _menuStore = menuStore ?? MenuStore() {
    _loadOrders();
    _loadMenu();
  }

  /// 启动时读回历史订单（异步，完成后 notifyListeners 刷新界面）。
  Future<void> _loadOrders() async {
    final loaded = await _orderStore.load();
    for (final o in loaded) {
      if (!_orders.any((e) => e.id == o.id)) {
        _orders.add(o);
      }
    }
    notifyListeners();
  }

  /// 启动时读回自定义菜单（有存过就用自定义的，否则用默认示例菜单）。
  Future<void> _loadMenu() async {
    final data = await _menuStore.load();
    if (data != null) {
      _categories = data.categories;
      _menu = data.items;
      notifyListeners();
    }
  }

  // ---- 当前选中的分类 ----
  String _selectedCategoryId = '';
  String get selectedCategoryId => _selectedCategoryId;

  void selectCategory(String id) {
    _selectedCategoryId = id;
    notifyListeners();
  }

  /// 回到「选种类」这一步。
  void clearCategory() {
    _selectedCategoryId = '';
    notifyListeners();
  }

  // ---- 购物车 ----
  // 用 map 存，**键 = 菜 + 选项 + 备注**：同一道菜不同选项/备注算不同的行。
  final Map<String, CartItem> _cart = {};
  List<CartItem> get cartItems => _cart.values.toList();
  bool get cartEmpty => _cart.isEmpty;

  int get cartCount =>
      _cart.values.fold(0, (sum, item) => sum + item.quantity);
  double get cartTotal =>
      _cart.values.fold(0.0, (sum, item) => sum + item.lineTotal);

  /// 点一道菜：同菜+同选项+同备注 已在购物车里就数量+1，否则新增一行。
  void addToCart(
    MenuItem item, {
    List<String> selections = const [],
    String note = '',
  }) {
    final key = CartItem(menuItem: item, selections: selections, note: note).key;
    final existing = _cart[key];
    if (existing != null) {
      existing.quantity++;
    } else {
      _cart[key] = CartItem(
        menuItem: item,
        selections: List.of(selections),
        note: note,
      );
    }
    notifyListeners();
  }

  /// [key] 是 [CartItem.key]（不是菜品 id）。
  void increment(String key) {
    final item = _cart[key];
    if (item != null) item.quantity++;
    notifyListeners();
  }

  void decrement(String key) {
    final item = _cart[key];
    if (item == null) return;
    item.quantity--;
    if (item.quantity <= 0) _cart.remove(key);
    notifyListeners();
  }

  /// 从购物车删掉某一行（[key] 是 [CartItem.key]）。
  void removeFromCart(String key) {
    _cart.remove(key);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  /// 把当前购物车转成订单行快照（带上所选项与备注）。
  List<OrderLine> _cartLines() => cartItems
      .map((c) => OrderLine(
            name: c.menuItem.name,
            quantity: c.quantity,
            unitPrice: c.menuItem.price,
            options: List.of(c.selections),
            note: c.note,
          ))
      .toList();

  /// 下单：把购物车变成一张**进行中**的订单（之后打“厨房单”给厨房）。
  /// 先记单、再清购物车、再落盘 —— 保证绝不丢单。
  Order? placeOrder({required String table}) {
    if (cartEmpty) return null;
    final order = Order(
      id: _nextOrderId(),
      createdAt: DateTime.now(),
      lines: _cartLines(),
      total: cartTotal,
      table: table,
      status: OrderStatus.inProgress,
    );
    _orders.insert(0, order);
    clearCart();
    _persistOrders();
    return order;
  }

  /// 追单：把购物车里的菜追加进一张**进行中**的订单。
  Order? appendToOrder(String orderId) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0 || cartEmpty) return null;

    final merged = List<OrderLine>.from(_orders[i].lines);
    for (final c in cartItems) {
      // 只有「菜名 + 单价 + 选项 + 备注」全都一样才合并
      final idx = merged.indexWhere((l) =>
          l.name == c.menuItem.name &&
          l.unitPrice == c.menuItem.price &&
          _sameList(l.options, c.selections) &&
          l.note == c.note);
      if (idx >= 0) {
        merged[idx] =
            merged[idx].copyWith(quantity: merged[idx].quantity + c.quantity);
      } else {
        merged.add(OrderLine(
          name: c.menuItem.name,
          quantity: c.quantity,
          unitPrice: c.menuItem.price,
          options: List.of(c.selections),
          note: c.note,
        ));
      }
    }
    final newTotal = merged.fold<double>(0, (sum, l) => sum + l.subtotal);
    _orders[i] = _orders[i].copyWith(lines: merged, total: newTotal);
    clearCart();
    _persistOrders();
    return _orders[i];
  }

  /// 结账：把一张进行中的单改成“已结单”（记支付方式、结单时间）。
  /// 之后打“顾客小票”。
  Order? closeOrder(String orderId, PaymentMethod method) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    _orders[i] = _orders[i].copyWith(
      paymentMethod: method,
      status: OrderStatus.completed,
      closedAt: DateTime.now(),
    );
    notifyListeners();
    _persistOrders();
    return _orders[i];
  }

  Order? findOrder(String orderId) {
    for (final o in _orders) {
      if (o.id == orderId) return o;
    }
    return null;
  }

  String _nextOrderId() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${_two(now.month)}${_two(now.day)}${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    // 加毫秒，保证重启后也不会撞号（避免持久化合并时误丢订单）
    return '$dateStr-${_orderCounter.toString().padLeft(3, '0')}-${now.millisecond}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// 删除某条订单（进行中或已结），并同步持久化。
  void deleteOrder(String orderId) {
    _orders.removeWhere((o) => o.id == orderId);
    notifyListeners();
    _persistOrders();
  }

  void _persistOrders() {
    // 后台保存，失败不致命（下次结账/删除会再存）
    _orderStore.save(_orders);
  }

  void _persistMenu() {
    _menuStore.save(MenuData(categories: _categories, items: _menu));
  }

  // ---------------- 分类管理 ----------------

  void addCategory(Category c) {
    _categories.add(c);
    notifyListeners();
    _persistMenu();
  }

  void updateCategory(Category c) {
    final i = _categories.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      _categories[i] = c;
      notifyListeners();
      _persistMenu();
    }
  }

  /// 删除分类，同时删除该分类下的菜品，并清选中状态。
  void deleteCategory(String id) {
    _categories.removeWhere((e) => e.id == id);
    _menu.removeWhere((m) => m.categoryId == id);
    if (_selectedCategoryId == id) _selectedCategoryId = '';
    notifyListeners();
    _persistMenu();
  }

  // ---------------- 菜品管理 ----------------

  void addMenuItem(MenuItem m) {
    _menu.add(m);
    notifyListeners();
    _persistMenu();
  }

  void updateMenuItem(MenuItem m) {
    final i = _menu.indexWhere((e) => e.id == m.id);
    if (i >= 0) {
      _menu[i] = m;
      notifyListeners();
      _persistMenu();
    }
  }

  void deleteMenuItem(String id) {
    _menu.removeWhere((m) => m.id == id);
    // 该菜在购物车里的所有行（可能因选项/备注不同有多行）一并移除
    _cart.removeWhere((_, v) => v.menuItem.id == id);
    notifyListeners();
    _persistMenu();
  }

  /// 两个字符串列表内容是否一致。
  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 生成一个新的分类/菜品 id（时间戳+自增，保证唯一）。
  String nextId() {
    _orderCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_orderCounter';
  }

  /// 恢复为默认示例菜单（用户改乱后一键还原）。
  void resetMenuToDefault() {
    _categories = List.of(sampleCategories);
    _menu = List.of(sampleMenu);
    if (_selectedCategoryId.isNotEmpty &&
        !_categories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = '';
    }
    notifyListeners();
    _persistMenu();
  }

  /// 用导入的菜单（例如 Excel）覆盖当前菜单，并持久化。
  /// 购物车会清空，避免里面还留着已经不存在的菜。
  void replaceMenu(MenuData data) {
    _categories = data.categories;
    _menu = data.items;
    if (_selectedCategoryId.isNotEmpty &&
        !_categories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = '';
    }
    _cart.clear();
    notifyListeners();
    _persistMenu();
  }
}
