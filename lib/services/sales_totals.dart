import '../models/order.dart';
import '../utils/pricing.dart';

/// 一段时间（比如一天）的营业汇总，**纯计算，不碰界面**（好写单元测试）。
class SalesTotals {
  /// 堂食 / 外卖 / **电话外卖** / **平台外卖**的营业额（都按订单最终应收算）。
  ///
  /// 电话外卖（打电话点的）、平台外卖（Uber / DiDi 这种 App 来的）各自单独一行：
  /// 方便老板看「电话单多少」「平台单多少」。
  final double dineIn;
  final double takeaway;
  final double phoneTakeaway;

  /// **平台外卖**的营业额（左侧「营业额」那几行里单独一行）。
  final double platformTakeaway;

  /// 小计 / 折扣 / 税 / 总营业额（= 各单应收之和）。
  final double subtotal;
  final double discount;
  final double tax;
  final double total;

  /// 现金收款：币种 → 金额（MXN / USD / RMB）。'' 表示没记币种。
  ///
  /// **平台外卖收的现金也在里面**（不单列：钱箱里的现金不分渠道）。
  final Map<String, double> cashByCurrency;

  /// **刷卡**（**不含平台外卖**：平台外卖刷的卡单独进 [platformCard]）。
  final double card;

  /// **平台外卖刷的卡**（「平台刷卡」那一行）。
  ///
  /// 为什么单独列：平台刷卡的到账 / 手续费跟店里自己的刷卡不一样，
  /// 老板数的时候要分开看。所以 [card] + [platformCard] = 全部刷卡。
  final double platformCard;

  final double qr;

  final int orderCount;

  const SalesTotals({
    required this.dineIn,
    required this.takeaway,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.cashByCurrency,
    required this.card,
    required this.qr,
    required this.orderCount,
    this.phoneTakeaway = 0,
    this.platformTakeaway = 0,
    this.platformCard = 0,
  });

  static const SalesTotals empty = SalesTotals(
    dineIn: 0,
    takeaway: 0,
    phoneTakeaway: 0,
    platformTakeaway: 0,
    subtotal: 0,
    discount: 0,
    tax: 0,
    total: 0,
    cashByCurrency: <String, double>{},
    card: 0,
    platformCard: 0,
    qr: 0,
    orderCount: 0,
  );

  /// 折扣 + 税之外的「小计」是否和总额不同（决定要不要多打几行）。
  bool get hasAdjustments =>
      round2(discount) != 0 || round2(tax) != 0 || round2(subtotal) != round2(total);

  /// 按支付方式分出来的合计（不含现金分币种）。
  ///
  /// 含**平台刷卡**：它也是刷卡收进来的钱，只是日结里单列一行。
  double get nonCashTotal => round2(card + platformCard + qr);
}

/// 把「已结单」列表算成汇总。
///
/// 规则：
/// - 营业额按**订单**算（堂食/外卖/电话外卖/平台外卖、小计/折扣/税、总营业额，
///   全部换成**本位币**）；
/// - 收款按**每一笔 payment** 算：刷卡/扫码是订单应收（本位币），
///   现金按**客人付的那个币种**分组，金额取「实收 - 找零」（= 留在钱箱里的钱）。
///
/// **平台外卖的收款**（按老板的要求）：
/// - 收的**现金** → 并进「现金」（跟堂食 / 外卖的现金一个钱箱，不单列）；
/// - 收的**刷卡** → 单独进 [SalesTotals.platformCard]（日结上叫「平台刷卡」），
///   所以 [SalesTotals.card] 里**不含**它（不会重复算）。
///
/// 所以外币现金那一行是「钱箱里实际有多少那种钱」，而总营业额始终是本位币，
/// 两者单位不同、不会对不上账（这也是收银员数钱时要看的数）。
SalesTotals computeSalesTotals(List<Order> orders) {
  double dineIn = 0, takeaway = 0, phoneTakeaway = 0, platformTakeaway = 0;
  double subtotal = 0, discount = 0, tax = 0, total = 0;
  double card = 0, platformCard = 0, qr = 0;
  final cash = <String, double>{};

  for (final o in orders) {
    total += o.total;
    subtotal += o.subtotal;
    discount += o.discountAmount;
    tax += o.taxAmount;
    // 堂食 / 外卖 / 电话外卖 / 平台外卖 分开算（四种加起来 = 总营业额）
    switch (o.orderType) {
      case OrderType.dineIn:
        dineIn += o.total;
        break;
      case OrderType.takeaway:
        takeaway += o.total;
        break;
      case OrderType.phonecallTakeaway:
        phoneTakeaway += o.total;
        break;
      case OrderType.platformTakeaway:
        platformTakeaway += o.total;
        break;
    }

    for (final p in o.effectivePayments) {
      switch (p.method) {
        case PaymentMethod.cash:
          // 现金按币种分开；金额 = 实收 - 找零（没记实收就用应收）。
          // 平台外卖的现金也走这里 —— 钱箱里的现金不分渠道。
          final net = p.received == null
              ? p.amount
              : round2(p.received! - (p.change ?? 0));
          cash[p.currencyCode] = (cash[p.currencyCode] ?? 0) + net;
          break;
        case PaymentMethod.card:
          // 平台外卖刷的卡单独算（日结右侧「平台刷卡」那一行）
          if (o.isPlatformTakeaway) {
            platformCard += p.amount;
          } else {
            card += p.amount;
          }
          break;
        case PaymentMethod.qr:
          // 扫码已经不做了；这里只是为了老数据还能统计出来
          qr += p.amount;
          break;
      }
    }
  }

  return SalesTotals(
    dineIn: round2(dineIn),
    takeaway: round2(takeaway),
    phoneTakeaway: round2(phoneTakeaway),
    platformTakeaway: round2(platformTakeaway),
    subtotal: round2(subtotal),
    discount: round2(discount),
    tax: round2(tax),
    total: round2(total),
    cashByCurrency: cash.map((k, v) => MapEntry(k, round2(v))),
    card: round2(card),
    platformCard: round2(platformCard),
    qr: round2(qr),
    orderCount: orders.length,
  );
}
