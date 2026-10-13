import '../l10n/app_strings.dart';
import '../models/order.dart';

/// 一张单「在哪」的短标签 —— 订单列表和日结明细**共用同一份写法**，
/// 免得两处对不上（对账时最怕这个）。
///
/// - 堂食 → `桌号 4`（没桌号写 `-`）；
/// - 外卖 → `外卖 #3`，起了名字就是 `外卖 张三 #3`；
/// - 电话外卖 → `电话外卖 张三 #3`。
String orderPlaceLabel(Order order) {
  if (order.isPhoneTakeaway) {
    return '${L10n.t('order.phonecallTakeaway')}'
        '${order.takeawayTag.isEmpty ? '' : ' ${order.takeawayTag}'}';
  }
  if (order.isTakeaway) {
    return '${L10n.t('order.takeaway')}'
        '${order.takeawayTag.isEmpty ? '' : ' ${order.takeawayTag}'}';
  }
  return '${L10n.t('order.table')} ${order.table.isEmpty ? '-' : order.table}';
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
