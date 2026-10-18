/// 金额格式化：加货币符号，保留两位小数。
String money(num value, String symbol) => '$symbol${value.toStringAsFixed(2)}';

/// 只保留两位小数（不带货币符号）。
String moneyNumber(num value) => value.toStringAsFixed(2);

/// **带正负号的金额**，给「特别备注加价」这种地方用：`+70`、`-60`、`+12.50`。
///
/// 整数不带小数尾巴（`+70` 而不是 `+70.00`）—— 备注价签要短，贴在文字后面才好看。
String signedAmount(num value) {
  final v = value.toDouble();
  final abs = v.abs();
  final text = abs == abs.roundToDouble()
      ? abs.toStringAsFixed(0)
      : abs.toStringAsFixed(2);
  return v < 0 ? '-$text' : '+$text';
}

/// 短时间格式（同步状态用）：`2025-01-31 09:05`。
String timeShort(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// 只要时分：`09:05`（考勤表里打卡时间用这个，格子窄）。
String timeHm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// 日期键：`2025-01-31`（按**本机日期**算，跨天/跨月都由它统一）。
///
/// 注：`PosController.dateKey` 是订单那边同样的东西；这里放一份给考勤/工具用，
/// 免得考勤代码去依赖点单控制器。
String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 时长写成 `9:25`（小时:分钟，分钟补零）。考勤「今天工作了多久」用。
String durationHm(Duration d) => '${d.inHours}:${_two(d.inMinutes % 60)}';

/// 时长写成**小时数**（一位小数，例如 `38.5`）。考勤表「本周工时」那一列用。
String hoursDecimal(Duration d) => (d.inMinutes / 60).toStringAsFixed(1);

String _two(int n) => n.toString().padLeft(2, '0');
