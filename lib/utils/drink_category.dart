/// 判断「这个种类是不是**饮料**」—— 厨师单要把饮料排在最后、并用虚线跟餐品分开。
///
/// 为什么按**名字**猜（而不是在设置里加一堆开关）：菜单是从 Excel 导入的，
/// 种类名字老板早就起好了（`饮料` / `Bebida` / `Drinks` / `Bebidas frias`），
/// 再让他一个个去勾"这是饮料"太重。名字里带下面这些词就算饮料。
///
/// ⚠️ 这只是个**启发式**：认不出（比如种类叫 `Extras`）就当餐品处理，不影响任何功能 ——
/// 最坏的情况只是饮料没被排到最后。想加词就往 [kDrinkCategoryHints] 里加。
library;

/// 名字里出现这些词 → 当成饮料种类（**不分大小写**，西语的重音也给了两种写法）。
///
/// 故意**不用**那些太容易误伤的短词（例如西语的 `te` 会命中 `Postre`）。
const List<String> kDrinkCategoryHints = <String>[
  // ---- 中文 ----
  '饮料', '饮品', '酒水', '冷饮', '热饮', '冰饮', '果汁', '奶茶', '咖啡', '汽水',
  '可乐', '啤酒', '鸡尾酒', '苏打',
  // ---- 西语（墨西哥店常见）----
  'bebida', 'jugo', 'refresco', 'soda', 'cafe', 'café', 'cerveza', 'coctel',
  'cóctel', 'malteada', 'licuado', 'agua', 'tecito', 'smoothie',
  // ---- 英语 ----
  'drink', 'beverage', 'juice', 'coffee', 'beer', 'cocktail', 'water',
  'shake', 'soda',
];

/// 这个名字的种类算不算**饮料**（空名字 → false）。
bool isDrinkCategory(String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  for (final hint in kDrinkCategoryHints) {
    if (n.contains(hint)) return true;
  }
  return false;
}
