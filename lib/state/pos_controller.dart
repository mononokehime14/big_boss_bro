import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../data/custom_menu_entry.dart';
import '../data/deleted_store.dart';
import '../data/menu_store.dart';
import '../data/order_store.dart';
import '../data/popularity_store.dart';
import '../data/sample_menu.dart';
import '../l10n/app_strings.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../utils/menu_sort.dart';
import '../utils/pricing.dart';

/// 核心状态：购物车、点单、结账、已结订单、菜单（分类+菜品）、流行度。
///
/// 用 ChangeNotifier，界面用 Provider 监听，订单/购物车/菜单一变就自动刷新。
/// - 已结订单通过 [OrderStore] 持久化（重启不丢）。
/// - 菜单（分类+菜品）通过 [MenuStore] 持久化，可在设置里自定义。
/// - **流行度**（每道菜/每个种类卖了多少份）通过 [PopularityStore] 持久化，
///   结账确认时累加，点单区可以按它排序。
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
  final PopularityStore _popularityStore;
  final DeletedOrdersStore _deletedStore;

  // 用来生成单号。
  int _orderCounter = 1;

  // ---------------- 后台同步（Supabase）的接线 ----------------
  //
  // PosController 只负责「标脏 + 提供快照 + 采纳服务器那份」，
  // 真正的网络搬运在 `services/sync_service.dart`（好测、也好拔掉）。
  // **任何情况下都不会因为同步而卡住收银**：这里的钩子都是「通知一下」而已。

  /// 这台设备的名字（由 SyncService 从设置里同步过来）。
  String deviceId = '';

  /// 本地订单变了（点单/改单/结账）→ SyncService 会防抖推一次。
  void Function()? onOrdersChanged;

  /// 本地菜单变了（菜品管理 / Excel 导入）→ SyncService 会推一次。
  void Function()? onMenuChanged;

  /// 本地删掉的单号（等下一次同步告诉服务器把行也删掉）。
  ///
  /// 会**存到本机**：哪怕删完就断网/退出，重启后还记得去后台删，
  /// 不然那些单会被下一次同步又拉回来。
  final List<String> _pendingDeleted = [];
  List<String> get pendingDeletedIds => List.unmodifiable(_pendingDeleted);

  Future<void> _persistDeleted() => _deletedStore.save(_pendingDeleted);

  /// 同步用：本地全部订单的快照。
  List<Order> ordersSnapshot() => List.of(_orders);

  /// 同步用：本地菜单的快照。
  MenuData menuSnapshot() =>
      MenuData(categories: List.of(_categories), items: List.of(_menu));

  /// 同步用：**采纳服务器那份**（拉回来的、或者推成功后服务器回给我们的）。
  ///
  /// 规则：本地没有 → 加进来；本地有 → 用服务器那份覆盖（服务器的 rev/updatedAt 是权威）。
  void adoptServerOrders(List<Order> incoming) {
    if (incoming.isEmpty) return;
    var changed = false;
    for (final remote in incoming) {
      // 本地刚删掉、还没来得及告诉后台的单 → **不要**又拉回来
      if (_pendingDeleted.contains(remote.id)) continue;
      final i = _orders.indexWhere((o) => o.id == remote.id);
      if (i < 0) {
        _orders.add(remote);
        changed = true;
      } else {
        // 本地这份如果还脏（有没推上去的改动），而服务器版本更高 → 还是听服务器的
        // （现实规矩：一张桌只在一台设备上操作，所以基本不会撞）
        _orders[i] = remote;
        changed = true;
      }
    }
    if (!changed) return;
    _sortOrders();
    notifyListeners();
    // 这是「服务器写本地」：不用再通知同步（不然会多跑一趟同步）
    _persistOrders(notifySync: false);
  }

  /// 同步用：把**所有**本地单标脏（「重置同步状态」时用：下次同步会把它们重新推一遍）。
  ///
  /// 只是标脏，**不删单子**、也不改金额。
  void markAllOrdersDirty() {
    if (_orders.isEmpty) return;
    for (var i = 0; i < _orders.length; i++) {
      _orders[i] = _orders[i].touch(deviceId: deviceId);
    }
    notifyListeners();
    _persistOrders();
  }

  /// 同步用：服务器上确实删掉了这些单（本地也清掉，不再重试）。
  void confirmDeletedPush(List<String> ids) {
    _pendingDeleted.removeWhere(ids.contains);
    unawaited(_persistDeleted());
  }

  /// 同步用：**服务器上这些单已经不存在了**（别的设备把它们删了）→ 本地也去掉。
  ///
  /// 跟 [confirmDeletedPush] 的区别：这里服务器上**已经没有**这些行了，
  /// 所以不需要再往「待删除」名单里加（也不用再推一次）。
  /// 只用于**进行中**的单 —— 已结账的历史留在本机（日结要用）。
  void dropOrdersRemovedOnServer(List<String> ids) {
    if (ids.isEmpty) return;
    final gone = ids.toSet();
    final before = _orders.length;
    _orders.removeWhere((o) => gone.contains(o.id));
    if (_orders.length == before) return;
    notifyListeners();
    // 这是「服务器写本地」：不用再通知同步（不然会多跑一趟）
    _persistOrders(notifySync: false);
  }

  /// 同步用：菜单被后台改过（服务器版本更高）→ 整体换掉本地的。
  ///
  /// 正在点的购物车不受影响（订单行是菜的快照）。
  void replaceMenuFromServer(MenuData data) {
    _categories = data.categories;
    _menu = data.items;
    if (_selectedCategoryId.isNotEmpty &&
        !_categories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = '';
    }
    notifyListeners();
    _persistMenu(markDirty: false);
  }

  List<Category> get categories => _categories;
  List<MenuItem> get menu => _menu;

  PosController({
    List<Category>? categories,
    List<MenuItem>? menu,
    OrderStore? orderStore,
    MenuStore? menuStore,
    PopularityStore? popularityStore,
    DeletedOrdersStore? deletedStore,
  })  : _categories = categories ?? List.of(sampleCategories),
        _menu = menu ?? List.of(sampleMenu),
        _orderStore = orderStore ?? OrderStore(),
        _menuStore = menuStore ?? MenuStore(),
        _popularityStore = popularityStore ?? PopularityStore(),
        _deletedStore = deletedStore ?? DeletedOrdersStore() {
    _loadOrders();
    _loadMenu();
    _loadSales();
    _loadDeleted();
  }

  /// 读回「本地删掉、还没告诉后台」的单号（重启后还要接着删）。
  Future<void> _loadDeleted() async {
    final ids = await _deletedStore.load();
    if (ids.isEmpty) return;
    for (final id in ids) {
      if (!_pendingDeleted.contains(id)) _pendingDeleted.add(id);
    }
    notifyListeners();
  }

  /// 订单按时间倒序（新的在前）—— 采纳服务器的单之后也要保持这个顺序。
  void _sortOrders() =>
      _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

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

  // ---------------- 流行度（卖出的份数）----------------
  //
  // 只统计**结账确认**过的那一单（见 [closeOrder]），键是菜品 id / 分类 id，
  // 值是**份数**（点 3 份就 +3）。点单区的「按流行度排序」用它。

  final Map<String, int> _itemSales = {};
  final Map<String, int> _categorySales = {};

  /// 菜品 id → 卖出的份数。
  Map<String, int> get itemSales => Map.unmodifiable(_itemSales);

  /// 分类 id → 卖出的份数。
  Map<String, int> get categorySales => Map.unmodifiable(_categorySales);

  /// 这道菜卖了多少份。
  int salesOfItem(String itemId) => _itemSales[itemId] ?? 0;

  /// 这个种类卖了多少份。
  int salesOfCategory(String categoryId) => _categorySales[categoryId] ?? 0;

  Future<void> _loadSales() async {
    final items = await _popularityStore.loadItems();
    final cats = await _popularityStore.loadCategories();
    if (items.isEmpty && cats.isEmpty) return;
    _itemSales
      ..clear()
      ..addAll(items);
    _categorySales
      ..clear()
      ..addAll(cats);
    notifyListeners();
  }

  void _persistSales() => _popularityStore.save(_itemSales, _categorySales);

  /// 清空流行度统计（想重新开始算时用）。
  void resetSales() {
    _itemSales.clear();
    _categorySales.clear();
    notifyListeners();
    _popularityStore.clear();
  }

  /// 结账确认时把这一单的份数记进流行度。
  ///
  /// 菜单里找不到的菜（换过菜单/老单）就跳过 —— 反正界面上也不会显示它。
  void _countSales(Order order) {
    for (final l in order.lines) {
      final item = menuItemForLine(l);
      if (item == null) continue;
      _itemSales[item.id] = (_itemSales[item.id] ?? 0) + l.quantity;
      _categorySales[item.categoryId] =
          (_categorySales[item.categoryId] ?? 0) + l.quantity;
    }
    _persistSales();
  }

  // ---------------- 排序（给点单区用）----------------

  /// 点单区要显示的**种类**（按 [mode] 排好）。
  ///
  /// [order] 是**本机记下来的顺序表**（`settings.menuOrder`），只在「默认」排序时用：
  /// 空表 = 菜单原本的顺序；用户在点单页拖过之后，就按他拖出来的顺序。
  ///
  /// **内置的「自定义」永远追加在最后**（它不属于真菜单，所以不参与排序、也不能拖）。
  List<Category> categoriesSorted(MenuSort mode,
          {List<String> order = const []}) =>
      <Category>[
        ...sortCategories(_categories, mode, _categorySales, order: order),
        customCategory(L10n.t('custom.category')),
      ];

  /// 某个种类下的**菜品**（按 [mode] 排好）。
  ///
  /// [order] 是**本机记下来的顺序表**（`settings.menuOrder`），只在「默认」排序时用
  /// （空表 = 菜单原本的顺序）。
  ///
  /// 「自定义」种类下永远只有一道「自定义」菜（点它会弹「金额 + 备注」框）。
  List<MenuItem> itemsSorted(String categoryId, MenuSort mode,
      {List<String> order = const []}) {
    if (categoryId == kCustomCategoryId) {
      return <MenuItem>[customMenuItem(L10n.t('custom.item'))];
    }
    return sortMenuItems(
      _menu.where((m) => m.categoryId == categoryId).toList(),
      mode,
      _itemSales,
      order: order,
    );
  }

  /// 真菜单 + 内置「自定义」（**只给界面用**：算分类下的菜品数量这类）。
  ///
  /// ⚠️ 推给后台的菜单要用 [menuSnapshot]（不含「自定义」）。
  List<MenuItem> get menuWithCustom =>
      <MenuItem>[..._menu, customMenuItem(L10n.t('custom.item'))];

  /// 点「自定义」那道菜：把「金额 + 备注」变成购物车里的一行。
  ///
  /// 备注会**当菜名**（小票/厨房单上直接显示备注内容），金额当单价，数量 1。
  /// 再点一次同样的「金额 + 备注」会并成一行（跟普通菜一样）。
  void addCustomItem({
    required String note,
    required double amount,
  }) {
    final item = customMenuItemWith(
      note: note,
      amount: amount,
      fallbackName: L10n.t('custom.item'),
    );
    addToCart(item);
  }

  /// 找这道菜在菜单里的定义：先按 [OrderLine.itemId]，找不到再按菜名（老数据没有 id）。
  MenuItem? menuItemForLine(OrderLine line) {
    if (line.itemId.isNotEmpty) {
      for (final m in _menu) {
        if (m.id == line.itemId) return m;
      }
    }
    for (final m in _menu) {
      if (m.name == line.name) return m;
    }
    return null;
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

  /// 购物车小计（不含折扣、不含「另加」的税）。
  double get cartSubtotal {
    var sum = 0.0;
    for (final item in _cart.values) {
      sum += item.lineTotal;
    }
    return round2(sum);
  }

  /// 购物车金额（历史字段：等于小计）。
  /// 要显示「含税合计」用 `PriceBreakdown.of(...)` ——
  /// 购物车面板就是这样把「已在单上 + 本次新增」的整桌合计算出来的。
  double get cartTotal => cartSubtotal;

  /// 购物车金额明细。折扣只在**结账**时才有，所以这里折扣恒为 0。
  PriceBreakdown cartPrice({double taxRate = 0, bool taxIncluded = true}) =>
      PriceBreakdown.of(
        subtotal: cartSubtotal,
        taxRate: taxRate,
        taxIncluded: taxIncluded,
      );

  /// 点一道菜：同菜+同选项+同备注 已在购物车里就数量增加，否则新增一行。
  ///
  /// [quantity] 是份数（点菜对话框里默认 1，可以直接输数字或按加号）。
  /// [notes] 是**特别备注**，可以好几条。
  void addToCart(
    MenuItem item, {
    List<String> selections = const [],
    List<String> notes = const [],
    int quantity = 1,
  }) {
    final qty = quantity < 1 ? 1 : quantity;
    final key = CartItem(menuItem: item, selections: selections, notes: notes).key;
    final existing = _cart[key];
    if (existing != null) {
      existing.quantity += qty;
    } else {
      _cart[key] = CartItem(
        menuItem: item,
        selections: List.of(selections),
        notes: List.of(notes),
        quantity: qty,
      );
    }
    notifyListeners();
  }

  /// 改购物车里的某一行（购物车里**点这一行**打开编辑框 → 保存后调这个）。
  ///
  /// 选项/备注改了 → 这一行的 key 也变了：把旧行拿掉，按新的 key 放回去；
  /// 如果正好和购物车里已有的另一行一样，就并到那一行（数量相加）。
  void updateCartItem(
    String oldKey, {
    required List<String> selections,
    required List<String> notes,
    required int quantity,
  }) {
    final old = _cart.remove(oldKey);
    if (old == null) {
      notifyListeners();
      return;
    }
    final qty = quantity < 1 ? 1 : quantity;
    final item = CartItem(
      menuItem: old.menuItem,
      selections: List.of(selections),
      notes: List.of(notes),
      quantity: qty,
    );
    final existing = _cart[item.key];
    if (existing != null) {
      existing.quantity += qty;
    } else {
      _cart[item.key] = item;
    }
    notifyListeners();
  }

  /// 改购物车里的一条**自定义行**（金额 / 备注 —— 备注就是它的菜名）。
  ///
  /// 「自定义」行的菜名和单价都来自弹窗，所以不能用 [updateCartItem]
  /// （那个只改选项/备注/份数，菜名和价格沿用原菜）。数量保持不变。
  void updateCustomCartItem(
    String oldKey, {
    required String note,
    required double amount,
  }) {
    final old = _cart.remove(oldKey);
    if (old == null) {
      notifyListeners();
      return;
    }
    final item = customMenuItemWith(
      note: note,
      amount: amount,
      fallbackName: L10n.t('custom.item'),
    );
    final fresh = CartItem(menuItem: item, quantity: old.quantity);
    final existing = _cart[fresh.key];
    if (existing != null) {
      existing.quantity += fresh.quantity;
    } else {
      _cart[fresh.key] = fresh;
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
    final min = item.menuItem.minQuantity;
    final next = item.quantity - 1;
    if (next < min) {
      // 「基础数量」列（例如套餐 2 份起）：减到最少份数就**停住**，
      // 要整行删掉用购物车里的 ✕（普通菜 min=1，减到 0 还是老行为：删掉这一行）
      if (min <= 1) _cart.remove(key);
    } else {
      item.quantity = next;
    }
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

  /// 把当前购物车转成订单行快照（带上所选项、**特别备注**、单位与**昵称**）。
  List<OrderLine> _cartLines() => cartItems
      .map((c) => OrderLine(
            name: c.menuItem.name,
            itemId: c.menuItem.id,
            quantity: c.quantity,
            unitPrice: c.unitPrice,
            options: List.of(c.selections),
            notes: List.of(c.notes),
            unit: c.menuItem.unit,
            // 昵称快照：点单界面 / 厨师单显示它，顾客小票还是打全名（name）
            nickName: c.menuItem.nickName,
          ))
      .toList();

  /// 下单：把购物车变成一张**进行中**的订单（之后打“厨房单”给厨房）。
  /// 先记单、再清购物车、再落盘 —— 保证绝不丢单。
  ///
  /// 桌号/堂食外卖用当前选中的（见 [selectTable]）。
  /// 税在下单时从设置里**快照**下来（以后改税率不影响已开的单）；
  /// 折扣要等结账时由收银员输入（见 [closeOrder]）。
  Order? placeOrder({
    String? table,
    double taxRate = 0,
    bool taxIncluded = true,
    String cashier = '',
  }) {
    if (cartEmpty) return null;
    final lines = _cartLines();
    final sub = lines.fold<double>(0, (sum, l) => sum + l.subtotal);
    final price = PriceBreakdown.of(
      subtotal: sub,
      taxRate: taxRate,
      taxIncluded: taxIncluded,
    );
    final order = Order(
      id: _nextOrderId(),
      createdAt: DateTime.now(),
      lines: lines,
      total: price.total,
      taxRate: taxRate,
      taxIncluded: taxIncluded,
      table: isTakeaway ? '' : (table ?? _selectedTable),
      // 外卖单的名字 = "保存过"的外卖单（起过名才会出现在下拉列表里，见 openTakeawayOrders）
      label: isTakeaway ? _selectedTakeawayLabel : '',
      // **所有单**都拿一个"当天从 1 开始"的号（堂食 / 外卖 / 电话外卖**共用**一条序列）：
      // 订单页的**默认排序**就是按它从大到小排；外卖单没起名字时，
      // 厨房单顶上打的那行大字也是它（见 Order.dailyNo）。
      dailyNo: _nextDailyNo(),
      orderType: _selectedType,
      status: OrderStatus.inProgress,
      cashier: cashier,
      // 同步：新单默认就是「脏」的（dirty=true），带上是哪台设备开的
      deviceId: deviceId,
    );
    _orders.insert(0, order);
    clearCart();
    _persistOrders();
    return order;
  }

  // ---- 先选桌：堂食（某个桌号）/ 外卖 / 电话外卖 ----

  String _selectedTable = '';

  /// 当前选的是哪种单：[OrderType.dineIn]（要桌号）/ [OrderType.takeaway] /
  /// [OrderType.phonecallTakeaway]（后两种都不用桌号）。
  OrderType _selectedType = OrderType.dineIn;

  String get selectedTable => _selectedTable;

  /// 当前选的目标类型（堂食 / 外卖 / 电话外卖）。
  OrderType get selectedType => _selectedType;

  /// 当前选的是不是「**不用桌号**」的单（外卖 / 电话外卖）。
  bool get isTakeaway => _selectedType != OrderType.dineIn;

  /// 当前选的是不是「**电话外卖**」（打电话点的）。
  bool get isPhoneTakeaway => _selectedType == OrderType.phonecallTakeaway;

  bool get hasTableSelected => isTakeaway || _selectedTable.isNotEmpty;

  /// 当前选中的**已命名外卖单**的名字（空 = 新外卖单 / 不是外卖）。
  ///
  /// 「起过名」就等于"保存过这张外卖单"：之后下拉列表里能选回来继续加菜
  /// （见 [openTakeawayOrders] / [selectTakeawayOrder]）。
  String _selectedTakeawayLabel = '';
  String get selectedTakeawayLabel => _selectedTakeawayLabel;

  /// **从「订单」页调出来改的那张单**（见 [focusOrder]）。
  ///
  /// 空 = 没有。它比"按桌号/名字找"优先，因为**没起名的外卖单**既没桌号也没名字，
  /// 只能靠单号把它调回购物车。
  String _focusedOrderId = '';

  /// 选桌：堂食传桌号；外卖 / 电话外卖传 `takeaway: true`。
  ///
  /// [type] 只在 `takeaway: true` 时有用：默认是**外卖**，
  /// 传 [OrderType.phonecallTakeaway] 就是**电话外卖**（打了个电话来点的）。
  ///
  /// 「外卖」这一项是**开新单**，所以会顺手把"选中的已保存外卖单"清掉。
  void selectTable(
    String table, {
    bool takeaway = false,
    OrderType type = OrderType.takeaway,
  }) {
    // 传 takeaway: true 时不允许再把类型设回堂食（那就矛盾了）
    _selectedType = takeaway
        ? (type == OrderType.dineIn ? OrderType.takeaway : type)
        : OrderType.dineIn;
    _selectedTable = takeaway ? '' : table;
    _selectedTakeawayLabel = '';
    _focusedOrderId = '';
    notifyListeners();
  }

  /// 选中一张**已保存（起过名）的外卖单**：下拉列表里点进来的那条就是它。
  ///
  /// 之后点「保存 / 厨房」都会加到**这张**单上（见 [openOrderForSelectedTable]），
  /// 也就是"回到那张单接着改"。
  void selectTakeawayOrder(Order order) {
    _selectedType = order.isTakeaway ? order.orderType : OrderType.takeaway;
    _selectedTable = '';
    _selectedTakeawayLabel = order.label.trim();
    _focusedOrderId = '';
    notifyListeners();
  }

  /// **从「订单」页点一张进行中的单 → 把它调到点单页改**（`orders_screen.dart` 用它）。
  ///
  /// 效果：目标切成那张单（桌号 / 电话外卖 / 外卖都行，**没起名的外卖单也能调出来**），
  /// 于是购物车面板里的「已在单上」就是它，可以加菜、改份数、改备注、删菜；
  /// 之后点「保存 / 厨房」都会加回**这张**单上。
  void focusOrder(Order order) {
    if (!order.isInProgress) return;
    _focusedOrderId = order.id;
    _selectedType = order.orderType;
    _selectedTable = order.isTakeaway ? '' : order.table;
    _selectedTakeawayLabel = order.isTakeaway ? order.label.trim() : '';
    notifyListeners();
  }

  /// 现在是不是"从订单页调出来改"的状态。
  bool get hasFocusedOrder => _focusedOrderId.isNotEmpty;

  /// 回到「选桌」这一步。
  void clearTable() {
    _selectedTable = '';
    _selectedType = OrderType.dineIn;
    _selectedTakeawayLabel = '';
    _focusedOrderId = '';
    notifyListeners();
  }

  /// 当前桌/外卖**已经下单、还没结账**的那张单（没有就 null）。
  ///
  /// - **堂食**：找这个桌号最新的一张进行中的单（可以继续加单）；
  /// - **外卖 / 电话外卖**：只有**起过名（= 保存过）**的外卖单才认得回来 ——
  ///   名字就是它的"位置"（见 [openTakeawayOrders]）。没起名的外卖单每单独立，
  ///   点完厨房直接结账就行（这里返回 null）。
  Order? openOrderForSelectedTable() {
    // ① 从「订单」页调出来改的那张单优先（它可能既没桌号也没名字）
    if (_focusedOrderId.isNotEmpty) {
      for (final o in _orders) {
        if (o.id == _focusedOrderId && o.isInProgress) return o;
      }
      // 那张单已经结账 / 被删了 → 忘掉它，回到按桌号/名字找
      _focusedOrderId = '';
    }
    if (!hasTableSelected) return null;
    if (isTakeaway) {
      final label = _selectedTakeawayLabel.trim();
      if (label.isEmpty) return null;
      for (final o in _orders) {
        if (o.isInProgress && o.isTakeaway && o.label.trim() == label) {
          return o;
        }
      }
      return null;
    }
    for (final o in _orders) {
      if (o.isInProgress &&
          o.orderType == OrderType.dineIn &&
          o.table == _selectedTable) {
        return o;
      }
    }
    return null;
  }

  /// **已保存的外卖单**（进行中 + 起过名的）：桌号下拉列表用它们"回到那张单接着改"。
  ///
  /// 结账确认之后它就不是「进行中」了 → 自然从列表里消失（这是需求里要的行为）。
  List<Order> openTakeawayOrders() => _orders
      .where((o) => o.isInProgress && o.isTakeaway && o.label.trim().isNotEmpty)
      .toList();

  /// **刚「保存 / 厨房 / 结账」动过的那张单**的 id（本地状态，不落盘）。
  ///
  /// 只给购物车那个「**结账**」按钮兜底用：购物车已经清空（比如刚点过「厨房」）、
  /// 而 [openOrderForSelectedTable] 又认不回来的时候，就结这一张。
  ///
  /// 为什么非要有它：**没起名字的外卖单**既没有桌号也没有名字，
  /// [openOrderForSelectedTable] 故意找不到它（外卖每单独立），
  /// 但"刚下的这一单"当然要能直接结账 —— 见 `checkoutOrderFlow`。
  String _lastTouchedOrderId = '';

  /// 见 [_lastTouchedOrderId]。已经结账 / 被删掉的会返回 null。
  Order? get lastTouchedOrder {
    if (_lastTouchedOrderId.isEmpty) return null;
    for (final o in _orders) {
      if (o.id == _lastTouchedOrderId && o.isInProgress) return o;
    }
    return null;
  }

  /// 记一下"这一单刚被保存 / 下厨房 / 结账动过"（只影响上面那个兜底）。
  void markTouchedOrder(String orderId) {
    if (orderId.isEmpty) return;
    _lastTouchedOrderId = orderId;
  }

  /// 这个外卖单名字能不能用？
  ///
  /// 不允许：空的、和**桌号**重名、和**别的进行中外卖单**重名。
  /// （[exceptOrderId] 是"别跟它自己比"—— 改自己的名字时用。）
  bool canUseTakeawayLabel(
    String label, {
    required List<String> tables,
    String exceptOrderId = '',
  }) {
    final v = label.trim();
    if (v.isEmpty) return false;
    for (final t in tables) {
      if (t.trim() == v) return false;
    }
    for (final o in _orders) {
      if (!o.isInProgress || !o.isTakeaway) continue;
      if (o.id == exceptOrderId) continue;
      if (o.label.trim() == v) return false;
    }
    return true;
  }

  /// 给一张**外卖单起名 / 改名**（= 保存进下拉列表），顺便可以存「要等多久」。
  ///
  /// - [label]：名字（空 = 不起名，但下面 [waitMinutes] 填了就仍然算"保存"）；
  /// - [waitMinutes]：要等几分钟（**电话外卖**用；0 = 不打这一行）。
  ///
  /// 两个都没填就返回 null（没什么可保存的）；重名要先自己用 [canUseTakeawayLabel] 检查。
  Order? setOrderLabel(
    String orderId,
    String label, {
    int? waitMinutes,
  }) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    final v = label.trim();
    final wait = waitMinutes ?? _orders[i].waitMinutes;
    if (v.isEmpty && wait <= 0) return null;
    _orders[i] = _orders[i]
        .copyWith(label: v, waitMinutes: wait < 0 ? 0 : wait)
        .touch(deviceId: deviceId);
    // 刚起名的这张单，顺手选中它 —— 免得用户以为还要再点一次下拉
    if (v.isNotEmpty && _orders[i].isTakeaway) selectTakeawayOrder(_orders[i]);
    notifyListeners();
    _persistOrders();
    return _orders[i];
  }

  /// **今天的单号**：当天已有的最大号 + 1（从 1 开始）。
  ///
  /// **堂食 / 外卖 / 电话外卖共用一条序列**（不分开算）：这样订单页按单号排的时候，
  /// 一天里谁先开的一目了然，也不会出现"三张单都是 #1"。
  ///
  /// 为什么从订单本身推、而不是存个计数器：重启/换设备都不会把号弄乱，也不占存储。
  /// 代价是"当天删掉最后一张单之后号会被复用"—— 无所谓，这个号只是给人看的
  /// （外卖单**没起名字**时，厨房单顶上那行大字打的就是它，见 Order.dailyNo）。
  int _nextDailyNo() {
    final today = _dayKey(DateTime.now());
    var max = 0;
    for (final o in _orders) {
      if (_dayKey(o.createdAt) != today) continue;
      if (o.dailyNo > max) max = o.dailyNo;
    }
    return max + 1;
  }

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  /// **下一张单会拿到的号**（下拉列表里显示「外卖 #4」这种，让人心里有数）。
  int get nextTakeawayNo => _nextDailyNo();

  /// 某个桌号上有多少「进行中」的菜（用于选桌界面显示）。
  int openItemCountForTable(String table) {
    var n = 0;
    for (final o in _orders) {
      if (o.isInProgress && o.orderType == OrderType.dineIn && o.table == table) {
        n += o.itemCount;
      }
    }
    return n;
  }

  /// 当前有几个「进行中」的外卖单（**不含**电话外卖）。
  int get openTakeawayCount => _openCount(OrderType.takeaway);

  /// 当前有几个「进行中」的**电话外卖**单。
  int get openPhoneTakeawayCount => _openCount(OrderType.phonecallTakeaway);

  int _openCount(OrderType type) {
    var n = 0;
    for (final o in _orders) {
      if (o.isInProgress && o.orderType == type) n++;
    }
    return n;
  }

  /// 追单：把购物车里的菜追加进一张**进行中**的订单。
  ///
  /// 合并规则：只有「菜名 + 单价 + 选项 + 备注」全都一样、而且**还没下过厨房**
  /// 的行才会合并数量 —— 已经打过厨房单的行（`sentToKitchen == true`）保持原样，
  /// 新加的菜另起一行（否则厨房会对不上账）。
  Order? appendToOrder(String orderId) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0 || cartEmpty) return null;

    final merged = List<OrderLine>.from(_orders[i].lines);
    for (final c in cartItems) {
      final idx = merged.indexWhere((l) =>
          !l.sentToKitchen &&
          l.name == c.menuItem.name &&
          l.unitPrice == c.unitPrice &&
          _sameList(l.options, c.selections) &&
          _sameList(l.notes, c.notes));
      if (idx >= 0) {
        merged[idx] =
            merged[idx].copyWith(quantity: merged[idx].quantity + c.quantity);
      } else {
        merged.add(OrderLine(
          name: c.menuItem.name,
          itemId: c.menuItem.id,
          quantity: c.quantity,
          unitPrice: c.unitPrice,
          options: List.of(c.selections),
          notes: List.of(c.notes),
          unit: c.menuItem.unit,
          nickName: c.menuItem.nickName, // 昵称跟着走（厨师单要显示）
          // 新加的菜**还没下厨房**：等「厨房」按钮打成功了才置 true
          sentToKitchen: false,
        ));
      }
    }
    final newTotal = merged.fold<double>(0, (sum, l) => sum + l.subtotal);
    // 用**这张单自己的**折扣/税重算应收（追单不能把折扣弄丢）
    final order = _orders[i];
    final price = PriceBreakdown.of(
      subtotal: newTotal,
      discountType: order.discountType,
      discountValue: order.discountValue,
      taxRate: order.taxRate,
      taxIncluded: order.taxIncluded,
    );
    // touch()：刷新本地改动时间 + 标脏（下次同步推给后台）
    _orders[i] =
        order.copyWith(lines: merged, total: price.total).touch(deviceId: deviceId);
    clearCart();
    _persistOrders();
    return _orders[i];
  }

  // ---------------- 下厨房（厨房单）----------------

  /// 这张单上**还没下过厨房**的行（= 下一张厨房单要打的菜）。
  ///
  /// 「保存」过的菜也算在这里：它们记在单上、但厨房还没收到，所以要打给厨房。
  List<OrderLine> unsentLines(String orderId) {
    final o = findOrder(orderId);
    if (o == null) return const <OrderLine>[];
    return o.lines.where((l) => !l.sentToKitchen).toList();
  }

  /// 把这张单上所有行标成「**已下厨房**」（厨房单**打成功之后**才调，见 `kitchenOrderFlow`）。
  ///
  /// 打失败就不标，这样收银员还能再点一次「厨房」重打，不会漏菜。
  Order? markOrderSent(String orderId) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    final o = _orders[i];
    if (!o.lines.any((l) => !l.sentToKitchen)) return o; // 都已经下过了
    _orders[i] = o
        .copyWith(
          lines: o.lines.map((l) => l.copyWith(sentToKitchen: true)).toList(),
        )
        .touch(deviceId: deviceId);
    notifyListeners();
    _persistOrders();
    return _orders[i];
  }

  // ---------------- 结账 / 收款 ----------------

  /// 结账：把一张**进行中**的单改成「已结单」，并记下这一笔收款。
  /// 之后打「顾客小票」。
  ///
  /// 参数说明（都和收款框里的输入对应）：
  /// - [discountType] / [discountValue]：收银员给的折扣（不打折传默认值）；
  /// - [currencyCode] + [exchangeRate]：客人付的币种与当时用的汇率
  ///   （本位币收款传空字符串 / 0）；
  /// - [receivedAmount] / [changeAmount]：**用客人那个币种计**的实收与找零；
  /// - [cashier]：经手人（账号显示名，打在小票上）。
  ///
  /// 注意：[Payment.amount] 记的是**本位币**的应收（订单总额），
  /// 所以「已收 = 应收」这个不变量永远成立，日结的营业额也永远对得上。
  Order? closeOrder(
    String orderId,
    PaymentMethod method, {
    DiscountType discountType = DiscountType.none,
    double discountValue = 0,
    String currencyCode = '',
    double exchangeRate = 0,
    double? receivedAmount,
    double? changeAmount,
    String cashier = '',
  }) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    final o = _orders[i];

    // 先按折扣算出最终应收，再记账（否则会按没打折的金额收钱）
    final price = PriceBreakdown.of(
      subtotal: o.subtotal,
      discountType: discountType,
      discountValue: discountValue,
      taxRate: o.taxRate,
      taxIncluded: o.taxIncluded,
    );
    final isCash = method == PaymentMethod.cash;
    final payment = Payment(
      method: method,
      amount: price.total,
      currencyCode: isCash ? currencyCode : '',
      received: isCash ? receivedAmount : null,
      change: isCash ? changeAmount : null,
      paidAt: DateTime.now(),
      cashier: cashier,
    );

    _orders[i] = o
        .copyWith(
          discountType: discountType,
          discountValue: discountValue,
          total: price.total,
          payments: <Payment>[payment],
          paymentMethod: method,
          status: OrderStatus.completed,
          closedAt: o.closedAt ?? DateTime.now(),
          currencyCode: isCash ? currencyCode : '',
          exchangeRate: isCash ? exchangeRate : 0,
          receivedAmount: isCash ? receivedAmount : null,
          changeAmount: isCash ? changeAmount : null,
          cashier: cashier.isEmpty ? o.cashier : cashier,
        )
        // 标脏：下一次同步会用 close_order() 把这个「已结账」同步上去
        .touch(deviceId: deviceId);
    notifyListeners();
    _persistOrders();
    // 流行度：**只在这里**（结账确认）把这一单的份数记进去，点单区可以按它排序
    _countSales(_orders[i]);
    return _orders[i];
  }

  /// 从一张**进行中**的单里删掉一行菜（购物车里的垃圾桶按钮用）。
  ///
  /// 用途：客人退菜 / 点错菜，在**点单界面**直接删（结账窗口里不再提供删除）。
  /// 删完会按**这张单自己的折扣和税**重算应收并落盘，所以
  /// 「购物车里显示的合计」「打出去的单子」「结账记的账」三边永远一致。
  ///
  /// 返回更新后的订单；以下情况返回 null（界面会禁用按钮，兜底用）：
  /// - 单不存在 / 已经不是进行中（已结单不能再改）；
  /// - [index] 越界；
  /// - **只剩最后一道菜**（删空就没法结账了，要取消整单请用「取消」）。
  Order? removeOrderLine(String orderId, int index) {
    final o = _orderAt(orderId);
    if (o == null) return null;
    if (index < 0 || index >= o.lines.length) return null;
    if (o.lines.length <= 1) return null;
    final lines = List<OrderLine>.from(o.lines)..removeAt(index);
    return _replaceLines(_indexOfOrder(orderId), lines);
  }

  /// 改一张**进行中**的单里的一行（购物车里点这道菜 → 编辑框保存后调）。
  ///
  /// - 单价按新选项**重算**（菜单里找得到这道菜的话）；
  /// - 只要内容有变化，这一行就标回「**未下厨**」：厨房手上还是老版本，
  ///   下次点「厨房」会重新打给它（你选的方案：不补打变动单，只改账单）。
  Order? updateOrderLine(
    String orderId,
    int index, {
    required List<String> selections,
    required List<String> notes,
    required int quantity,
  }) {
    final o = _orderAt(orderId);
    if (o == null) return null;
    if (index < 0 || index >= o.lines.length) return null;
    if (quantity < 1) return null;

    final old = o.lines[index];
    final item = menuItemForLine(old);
    final unitPrice =
        item == null ? old.unitPrice : item.unitPriceFor(selections);
    final changed = old.quantity != quantity ||
        !_sameList(old.options, selections) ||
        !_sameList(old.notes, notes) ||
        (old.unitPrice - unitPrice).abs() > 0.001;
    if (!changed) return o; // 什么都没改：不动它，保持原状态

    final lines = List<OrderLine>.from(o.lines);
    lines[index] = old.copyWith(
      quantity: quantity,
      options: List.of(selections),
      notes: List.of(notes),
      unitPrice: unitPrice,
      sentToKitchen: false,
    );
    return _replaceLines(_indexOfOrder(orderId), lines);
  }

  /// 改「已在单上」的一条**自定义行**（金额 / 备注 —— 备注就是菜名）。
  ///
  /// 跟 [updateOrderLine] 的区别：菜名和单价也一起改（自定义行的菜名就是备注）。
  /// 改过的行同样标回「未下厨」，下次点「厨房」会重新打给厨房。
  Order? updateCustomOrderLine(
    String orderId,
    int index, {
    required String note,
    required double amount,
  }) {
    final o = _orderAt(orderId);
    if (o == null) return null;
    if (index < 0 || index >= o.lines.length) return null;
    final old = o.lines[index];
    final name = note.trim().isEmpty ? L10n.t('custom.item') : note.trim();
    final changed = old.name != name || (old.unitPrice - amount).abs() > 0.001;
    if (!changed) return o; // 什么都没改：不动它

    final lines = List<OrderLine>.from(o.lines);
    lines[index] = old.copyWith(
      name: name,
      itemId: kCustomItemId,
      unitPrice: amount,
      sentToKitchen: false,
    );
    return _replaceLines(_indexOfOrder(orderId), lines);
  }

  /// 加减一份已经记在单上的菜（购物车里的 +/- 按钮）。
  ///
  /// 减到 0 就删掉这一行（只剩一行时不给删）；改完同样标回「未下厨」。
  Order? changeOrderLineQuantity(String orderId, int index, int delta) {
    final o = _orderAt(orderId);
    if (o == null) return null;
    if (index < 0 || index >= o.lines.length) return null;
    final line = o.lines[index];
    // 「基础数量」列（例如套餐 2 份起）：减到最少份数就停住，不再往下减
    final min = menuItemForLine(line)?.minQuantity ?? 1;
    final qty = line.quantity + delta;
    if (qty < min) {
      // 普通菜（min=1）减到 0 还是老行为：删掉这一行
      if (min <= 1) return removeOrderLine(orderId, index);
      return o;
    }

    final lines = List<OrderLine>.from(o.lines);
    lines[index] = line.copyWith(quantity: qty, sentToKitchen: false);
    return _replaceLines(_indexOfOrder(orderId), lines);
  }

  /// 这张单（必须是**进行中**的，否则返回 null）。
  Order? _orderAt(String orderId) {
    final i = _indexOfOrder(orderId);
    if (i < 0) return null;
    final o = _orders[i];
    return o.isInProgress ? o : null;
  }

  int _indexOfOrder(String orderId) =>
      _orders.indexWhere((o) => o.id == orderId);

  /// 换掉第 [i] 张单的行，并按这张单自己的折扣/税重算应收、落盘。
  Order _replaceLines(int i, List<OrderLine> lines) {
    final o = _orders[i];
    final sub = round2(lines.fold<double>(0, (sum, l) => sum + l.subtotal));
    final price = PriceBreakdown.of(
      subtotal: sub,
      discountType: o.discountType,
      discountValue: o.discountValue,
      taxRate: o.taxRate,
      taxIncluded: o.taxIncluded,
    );
    _orders[i] =
        o.copyWith(lines: lines, total: price.total).touch(deviceId: deviceId);
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

  /// 日结用的日期键：`yyyy-MM-dd`。
  static String dateKey(DateTime d) =>
      '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// 某一天「已结单」的订单（日结用）。
  List<Order> completedOrdersOn(String dateKey) => _orders
      .where((o) =>
          o.status == OrderStatus.completed &&
          PosController.dateKey(o.closedAt ?? o.createdAt) == dateKey)
      .toList();

  String _nextOrderId() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${_two(now.month)}${_two(now.day)}${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    // 加毫秒，保证重启后也不会撞号（避免持久化合并时误丢订单）
    return '$dateStr-${_orderCounter.toString().padLeft(3, '0')}-${now.millisecond}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// 删除某条订单（进行中或已结），并同步持久化。
  ///
  /// 同步：记进「待删除」名单，下一次同步让后台也把这一行删掉
  /// （本地是立即删掉的，界面不用等网络）。
  void deleteOrder(String orderId) {
    _orders.removeWhere((o) => o.id == orderId);
    if (!_pendingDeleted.contains(orderId)) _pendingDeleted.add(orderId);
    unawaited(_persistDeleted());
    notifyListeners();
    _persistOrders();
  }

  void _persistOrders({bool notifySync = true}) {
    // 后台保存，失败不致命（下次结账/删除会再存）
    _orderStore.save(_orders);
    // 通知同步服务：本地变了（它会防抖推一次，推不动也不影响收银）
    //
    // 注意：**采纳服务器那份**的时候不要再通知（notifySync: false），
    // 否则「同步 → 写本地 → 又要同步」会多跑一趟无用功。
    if (notifySync) onOrdersChanged?.call();
  }

  /// 存菜单。[markDirty] = true 表示「本地改的」（要推给后台）；
  /// 从服务器拉下来的菜单用 false（它本来就是后台那份）。
  void _persistMenu({bool markDirty = true}) {
    _menuStore.save(MenuData(categories: _categories, items: _menu));
    if (markDirty) onMenuChanged?.call();
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
