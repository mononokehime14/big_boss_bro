import '../l10n/app_strings.dart';
import '../models/order.dart';

/// 一张单「在哪」的短标签 —— 订单列表和日结明细**共用同一份写法**，
/// 免得两处对不上（对账时最怕这个）。
///
/// - 堂食 → `桌号 4  #12`（没桌号写 `-`）；
/// - 外卖 → `外卖 #3`，起了名字就是 `外卖 张三 #3`；
/// - 电话外卖 → `电话外卖 张三 #3`；
/// - **分单** → 上面那串后面加 `-分单1`（例：`桌号 4-分单1`，分单不带 `#号`）。
///
/// `#N` 是**当天从 1 开始**的单号（堂食 / 外卖 / 电话外卖**共用一条序列**，
/// 见 `PosController._nextDailyNo`）—— 订单页的默认排序就按它从大到小。
String orderPlaceLabel(Order order) {
  // 外卖 / 电话外卖：名字和号都已经在 `takeawayTag` 里（`名字 #号`）
  final String base;
  if (order.isPhoneTakeaway) {
    base = '${L10n.t('order.phonecallTakeaway')}'
        '${order.takeawayTag.isEmpty ? '' : ' ${order.takeawayTag}'}';
  } else if (order.isTakeaway) {
    base = '${L10n.t('order.takeaway')}'
        '${order.takeawayTag.isEmpty ? '' : ' ${order.takeawayTag}'}';
  } else {
    // 堂食：桌号 + 单号（老数据没有号 → dailyNo = 0，那就不显示）
    final table =
        '${L10n.t('order.table')} ${order.table.isEmpty ? '-' : order.table}';
    // 分单不再带母单的单号（`桌号 4  #12-分单1` 太长太乱）
    base = (!order.isSplit && order.dailyNo > 0)
        ? '$table  #${order.dailyNo}'
        : table;
  }
  if (!order.isSplit) return base;
  return '$base-${L10n.t('split.suffix')}${order.splitNo}';
}

/// 支付方式的显示文字：混付（老数据里的 AA）写「混合」，
/// 没付过钱（进行中的单）写 `-`。
String orderPaymentLabel(Order order) {
  final methods = order.payments.map((p) => p.method).toSet();
  if (methods.length > 1) return L10n.t('payment.mixed');
  return orderPaymentMethodLabel(order.paymentMethod);
}

/// 单个支付方式的显示文字（null = 还没付钱）。
String orderPaymentMethodLabel(PaymentMethod? m) {
  switch (m) {
    case PaymentMethod.cash:
      return L10n.t('payment.cash');
    case PaymentMethod.card:
      return L10n.t('payment.card');
    case PaymentMethod.qr:
      return L10n.t('payment.qr');
    case null:
      return '-';
  }
}
