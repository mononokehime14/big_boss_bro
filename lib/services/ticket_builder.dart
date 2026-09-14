import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/order.dart';
import 'escpos.dart';
import 'receipt_layout.dart';

/// 把订单/设置变成小票的行文本（所有打印通道共用）。
///
/// 小票上的表头文字用 [Settings.receiptLang]（可独立于界面语言）；
/// 菜品名来自菜单/Excel，不翻译。
class TicketBuilder {
  static String _t(Settings s, String key) => L10n.tFor(s.receiptLang, key);

  /// 顾客小票（结账时打）：含单价/金额/合计/支付方式。
  static List<TicketLine> receiptLines(Order order, Settings settings) {
    final data = ReceiptData(
      storeName: settings.storeName,
      currency: settings.currencySymbol,
      orderId: order.id,
      createdAt: order.createdAt,
      paymentMethodLabel: _methodLabel(settings, order.paymentMethod),
      lines: order.lines,
      total: order.total,
      thankyou: _t(settings, 'order.thankyou'),
      paperWidth: settings.paperWidth,
      labels: ReceiptLabels(
        colName: _t(settings, 'receipt.colName'),
        colQty: _t(settings, 'receipt.colQty'),
        colUnit: _t(settings, 'receipt.colUnit'),
        colAmt: _t(settings, 'receipt.colAmt'),
        labelTotal: _t(settings, 'receipt.labelTotal'),
        labelPay: _t(settings, 'receipt.labelPay'),
      ),
    );
    return buildReceiptLines(data).map((l) => TicketLine(l)).toList();
  }

  /// 厨房单（下单/追单时打）：只有菜名+数量+桌号。
  static List<TicketLine> kitchenLines(
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
        title: _t(settings, 'kitchen.title'),
        labelTable: _t(settings, 'order.table'),
        colName: _t(settings, 'kitchen.colName'),
        colQty: _t(settings, 'kitchen.colQty'),
        append: _t(settings, 'kitchen.append'),
      ),
    );
    return buildKitchenLines(data).map((l) => TicketLine(l)).toList();
  }

  /// 测试页（内容已按需求固定）。
  ///
  /// 每一行的用途：
  /// - `----` 刻度尺：长度 = 当前纸宽应有的列数，**应顶到纸的两边**。
  /// - `ASCII` / `Espanol: Gracias`：基本打印 + 西语。
  /// - `中文A(FS&)` / `中文B(ESC t)`：**无视当前编码设置**，强制用两种方式打中文，
  ///   哪一行正常就说明打印机支持中文、且用哪种方式进中文模式。
  /// - `[BIG]`：双倍大小的字。**变大 = ESC/POS 指令真的生效了**（RAW 通道正常）；
  ///   和普通字一样大 = 中间那层（多半是 Windows 驱动）没把指令透传 → 乱码的根源在它。
  static List<TicketLine> testLines(Settings settings) {
    final cols = receiptColumns(settings.paperWidth);
    final ruler = '-' * cols;
    return <TicketLine>[
      TicketLine(settings.storeName.isEmpty ? 'TEST PAGE' : settings.storeName),
      TicketLine('------ TEST PAGE ------'),
      TicketLine('Paper ${settings.paperWidth}mm  Cols $cols'),
      TicketLine(
          'Codec ${settings.receiptCodec}  FontA ${settings.useFontA ? 'on' : 'off'}'),
      TicketLine(ruler),
      TicketLine('ASCII  : 0123456789 ABCDEFG'),
      TicketLine('Espanol: Gracias'),
      TicketLine('中文A(FS&): 恭喜您，打印成功！',
          raw: gbkProbeFs('中文A(FS&): 恭喜您，打印成功！')),
      TicketLine('中文B(ESCt): 恭喜您，打印成功！',
          raw: gbkProbeEscT('中文B(ESCt): 恭喜您，打印成功！')),
      TicketLine('', raw: doubleSizeBytes('[BIG] ESC/POS CHECK')),
      TicketLine(ruler),
      TicketLine('ruler should touch both edges'),
    ];
  }

  static String _methodLabel(Settings s, PaymentMethod? m) {
    switch (m) {
      case PaymentMethod.cash:
        return _t(s, 'payment.cash');
      case PaymentMethod.card:
        return _t(s, 'payment.card');
      case PaymentMethod.qr:
        return _t(s, 'payment.qr');
      case null:
        return '-';
    }
  }
}
