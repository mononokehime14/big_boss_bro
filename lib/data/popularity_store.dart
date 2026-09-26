import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 「流行度」的本机存储：**每道菜 / 每个种类卖出了多少份**。
///
/// 存的结构（一个 JSON 字符串）：
/// ```json
/// { "items": { "菜品id": 12, "另一个id": 3 },
///   "categories": { "分类id": 30 } }
/// ```
///
/// 什么时候写：**结账确认**时（`PosController.closeOrder`）按这一单的份数累加，
/// 见 `PosController._countSales`。点单区的「按流行度排序」就读它。
class PopularityStore {
  static const _kSales = 'menu_sales';

  /// 读「菜品 id → 份数」。
  Future<Map<String, int>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_kSales), 'items');
  }

  /// 读「分类 id → 份数」。
  Future<Map<String, int>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_kSales), 'categories');
  }

  /// 整份保存（两个表一起写）。
  Future<void> save(
    Map<String, int> items,
    Map<String, int> categories,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSales,
      jsonEncode({'items': items, 'categories': categories}),
    );
  }

  /// 清空统计（设置里想「重新开始算流行度」时用）。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSales);
  }

  static Map<String, int> _decode(String? raw, String key) {
    if (raw == null) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded[key] is Map) {
        final out = <String, int>{};
        (decoded[key] as Map).forEach((k, v) {
          if (v is num) out[k.toString()] = v.toInt();
        });
        return out;
      }
    } catch (_) {}
    return <String, int>{};
  }
}
