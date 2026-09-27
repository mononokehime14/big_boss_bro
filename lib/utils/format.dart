/// 金额格式化：加货币符号，保留两位小数。
String money(num value, String symbol) => '$symbol${value.toStringAsFixed(2)}';

/// 只保留两位小数（不带货币符号）。
String moneyNumber(num value) => value.toStringAsFixed(2);

/// 短时间格式（同步状态用）：`2025-01-31 09:05`。
String timeShort(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');
