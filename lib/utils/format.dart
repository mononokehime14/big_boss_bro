/// 金额格式化：加货币符号，保留两位小数。
String money(num value, String symbol) => '$symbol${value.toStringAsFixed(2)}';

/// 只保留两位小数（不带货币符号）。
String moneyNumber(num value) => value.toStringAsFixed(2);
