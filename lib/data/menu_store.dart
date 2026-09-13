import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/category.dart';
import '../models/menu_item.dart';

/// 菜单数据（分类 + 菜品）。
class MenuData {
  final List<Category> categories;
  final List<MenuItem> items;
  const MenuData({required this.categories, required this.items});
}

/// 菜单持久化：把分类和菜品以 JSON 存到本机，可自定义菜单。
class MenuStore {
  static const _key = 'menu_data';

  Future<void> save(MenuData data) async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'categories': data.categories.map((c) => c.toJson()).toList(),
      'items': data.items.map((m) => m.toJson()).toList(),
    };
    await prefs.setString(_key, jsonEncode(map));
  }

  /// 读回；没有存过或数据损坏时返回 null（由状态层决定用默认菜单）。
  Future<MenuData?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cats = (map['categories'] as List)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
      final items = (map['items'] as List)
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return MenuData(categories: cats, items: items);
    } catch (_) {
      return null;
    }
  }
}
