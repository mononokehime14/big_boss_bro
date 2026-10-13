import '../models/category.dart';
import '../models/menu_item.dart';

/// 内置的「自定义」种类 / 菜品的 **id**（固定值，正常菜单不会撞 —— Excel 导入的 id 是菜名）。
///
/// 用途：客人点了菜单上没有的东西（临时加菜、按重量算的菜、外卖备注…）——
/// 选它就弹一个框：**金额 + 特别备注**，备注会**当菜名**打在小票 / 厨房单上。
///
/// 三个要点：
/// 1. 它**不进菜单数据**：既不写本机菜单存储，也**不推给后台** ——
///    `PosController.menuSnapshot()` 推上去的永远是"真菜单"，
///    「自定义」是渲染时才追加进去的（见 `categoriesSorted` / `itemsSorted`）；
/// 2. 它**永远排在种类列表最后**，不管排序方式怎么选（`MenuSort` 只管真菜单）；
/// 3. 它的**常用备注**存在 `Settings.notesByCategory['__custom__']` 里，
///    跟别的种类一样会**云同步**（`store_settings_sync.dart` 的 `toData`）。
const String kCustomCategoryId = '__custom__';
const String kCustomItemId = '__custom__';

/// 「自定义」种类的固定底色（**深琥珀**）：一眼能和真菜单的分类区分开，
/// 也够深、白字压得住（浅琥珀配白字看不清）。
const int kCustomCategoryColor = 0xFFB26A00;

/// 「自定义」种类（名字由调用方给，跟随界面语言）。
Category customCategory(String name) => Category(
      id: kCustomCategoryId,
      name: name,
      emoji: '✍️',
      colorValue: kCustomCategoryColor,
    );

/// 「自定义」菜品（价格恒为 0 —— 真正的金额在弹窗里输）。
MenuItem customMenuItem(String name) => MenuItem(
      id: kCustomItemId,
      name: name,
      price: 0,
      emoji: '✍️',
      categoryId: kCustomCategoryId,
    );

/// 真正下单用的「自定义」菜：**备注当菜名**（用户选的做法，厨房/小票直接看到「生日蛋糕」）、
/// 金额当单价、数量 1。
///
/// 备注为空就退回 [fallbackName]（=「自定义」这三个字，界面语言不同会不一样）。
MenuItem customMenuItemWith({
  required String note,
  required double amount,
  required String fallbackName,
}) {
  final v = note.trim();
  return customMenuItem(v.isEmpty ? fallbackName : v).copyWith(price: amount);
}
