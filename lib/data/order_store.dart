import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';

/// 订单历史持久化：把已结订单以 JSON 存到本机，App 重启后仍可读回。
class OrderStore {
  static const _key = 'orders_history';

  Future<List<Order>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏时返回空，不让 App 崩溃
      return const [];
    }
  }

  Future<void> save(List<Order> orders) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(orders.map((o) => o.toJson()).toList());
    await prefs.setString(_key, json);
  }
}
