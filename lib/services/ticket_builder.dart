import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/order.dart';
import 'receipt_layout.dart';

/// 把订单/设置变成小票的行文本（所有打印通道共用）。
class TicketBuilder {
  /// 顾客小票（结账时打）：含单价/金额/合计/支付方式。
  static List<String> receiptLines(Order order, Settings settings) {
    final data = ReceiptData(
      storeName: settings.storeName,
      currency: settings.currencySymbol,
      orderId: order.id,
      createdAt: order.createdAt,
      paymentMethodLabel: _methodLabel(order.paymentMethod),
      lines: order.lines,
      total: order.total,
      thankyou: L10n.t('order.thankyou'),
      paperWidth: settings.paperWidth,
      labels: ReceiptLabels(
        colName: L10n.t('receipt.colName'),
        colQty: L10n.t('receipt.colQty'),
        colUnit: L10n.t('receipt.colUnit'),
        colAmt: L10n.t('receipt.colAmt'),
        labelTotal: L10n.t('receipt.labelTotal'),
        labelPay: L10n.t('receipt.labelPay'),
      ),
    );
    return buildReceiptLines(data);
  }

  /// 厨房单（下单/追单时打）：只有菜名+数量+桌号。
  static List<String> kitchenLines(
    Order order,
    Settings settings, {
    bool isAppend = false,
  }) {
    final data = KitchenData(
      table: order.table,
      orderId: order.id,
      createdAt: order.createdAt,
      lines: order.lines,
      paperWidth: settings.paperWidth,
      isAppend: isAppend,
      labels: KitchenLabels(
        title: L10n.t('kitchen.title'),
        labelTable: L10n.t('order.table'),
        colName: L10n.t('kitchen.colName'),
        colQty: L10n.t('kitchen.colQty'),
        append: L10n.t('kitchen.append'),
      ),
    );
    return buildKitchenLines(data);
  }

  /// 测试页：验证中文编码、纸宽、对齐。
  static List<String> testLines(Settings settings) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return <String>[
      if (settings.storeName.isNotEmpty) settings.storeName,
      '--- TEST ${two(now.hour)}:${two(now.minute)} ---',
      L10n.t('print.test.content'),
      '58mm / 80mm width:',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      '0123456789012345678901234567',
      '中文测试：牛肉炒饭 ￥28.00',
    ];
  }

  static String _methodLabel(PaymentMethod? m) {
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
}
