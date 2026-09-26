/// 金额计算规则（**全 App 只有这一份**：购物车、订单、小票、日结都调它）。
///
/// 为什么单独抽出来：折扣和税一旦在多处各写一遍，早晚会出现
/// 「购物车显示 100、小票打 98」这种对不上账的问题。规则集中在这里，
/// 再用单元测试锁死（见 `test/pricing_test.dart`）。
library;

/// 金额统一保留两位小数（四舍五入到「分」）。
///
/// 浮点数直接相加会出现 0.30000000000000004 这种值，所以每次算完都过一遍它。
double round2(double v) => (v * 100).roundToDouble() / 100;

/// 折扣方式。
enum DiscountType {
  /// 不打折。
  none('none'),

  /// 按百分比打折：`discountValue = 10` 表示**减 10%**（客人付 9 折）。
  percent('percent'),

  /// 直接减固定金额：`discountValue = 20` 表示减 20 元。
  amount('amount');

  final String id;
  const DiscountType(this.id);

  static DiscountType fromId(String? id) => DiscountType.values.firstWhere(
        (e) => e.id == id,
        orElse: () => DiscountType.none,
      );
}

/// 一单的金额明细。
///
/// 计算顺序是**先打折、后算税**（这也是各地税务的通行做法）：
/// ```
/// 小计 subtotal   = Σ（单价 × 数量）
/// 折扣 discount   = 小计 × 折扣率  或  固定金额（不会超过小计）
/// 净额 net        = 小计 - 折扣
/// 税   tax        = 不含税时 net × 税率；含税时 net - net×100/(100+税率)
/// 应收 total      = 含税 ? net : net + tax
/// ```
class PriceBreakdown {
  final double subtotal;
  final double discount;

  /// 打折之后、加税之前的金额。
  final double net;

  /// 税额（不含税时是「另加」的税；含税时是「已含在里面」的税，仅用于展示）。
  final double tax;

  /// 最终应收。
  final double total;

  const PriceBreakdown({
    required this.subtotal,
    required this.discount,
    required this.net,
    required this.tax,
    required this.total,
  });

  bool get hasDiscount => discount > 0;
  bool get hasTax => tax > 0;

  /// 明细是否和小计不同（= 需要在小票上多打几行）。
  bool get hasAdjustments => hasDiscount || hasTax;

  static PriceBreakdown of({
    required double subtotal,
    DiscountType discountType = DiscountType.none,
    double discountValue = 0,
    double taxRate = 0,
    bool taxIncluded = true,
  }) {
    final sub = round2(subtotal < 0 ? 0 : subtotal);

    double disc;
    switch (discountType) {
      case DiscountType.none:
        disc = 0;
        break;
      case DiscountType.percent:
        // 折扣率限制在 0~100，防止手滑输入 200
        final pct = discountValue.clamp(0.0, 100.0);
        disc = round2(sub * pct / 100);
        break;
      case DiscountType.amount:
        // 减免金额不能超过小计（否则应收变负数）
        disc = round2(discountValue.clamp(0.0, sub));
        break;
    }

    final net = round2(sub - disc);
    final rate = taxRate < 0 ? 0.0 : taxRate;
    final double tax;
    if (rate == 0) {
      tax = 0;
    } else if (taxIncluded) {
      // 价内含税：从净额里倒推税额，应收不变
      tax = round2(net - net * 100 / (100 + rate));
    } else {
      // 价外税：在净额上加税
      tax = round2(net * rate / 100);
    }
    final total = taxIncluded ? net : round2(net + tax);

    return PriceBreakdown(
      subtotal: sub,
      discount: disc,
      net: net,
      tax: tax,
      total: total,
    );
  }

  @override
  String toString() =>
      'PriceBreakdown(subtotal: $subtotal, discount: $discount, '
      'net: $net, tax: $tax, total: $total)';
}

// ---------------------------------------------------------------------------
// 币种换算（MXN / USD / RMB）
// ---------------------------------------------------------------------------

/// 汇率的口径：**1 个外币 = 多少「店里收钱的货币」**。
///
/// 例：店里收 MXN、1 USD = 18.50 MXN → `rate = 18.5`；本位币自己的汇率恒为 1。
/// 汇率是**老板手填**的（见「菜品管理 → 汇率」），不联网：
/// 填 0 表示**没设汇率** → 界面上不换算，也不能用那个币种收款。
///
/// 本位币金额 → 外币金额（收钱时要告诉客人「你这个币种要付多少」）。
double toForeign(double baseAmount, double rate) {
  if (rate <= 0) return round2(baseAmount);
  return round2(baseAmount / rate);
}

/// 外币金额 → 本位币金额。
double toBase(double foreignAmount, double rate) {
  if (rate <= 0) return round2(foreignAmount);
  return round2(foreignAmount * rate);
}

// ---------------------------------------------------------------------------
// 现金收款的「快捷金额」（结账框里实收框下方那几个标签）
// ---------------------------------------------------------------------------

/// 实收的快捷金额：**第一个永远是「正好」，后面是邻近的整数**（最多三个）。
///
/// 收银员按客人递来的钞票点一下就行，不用敲键盘。凑整的档位依次是
/// 10 / 50 / 100 / 200 / 500 / 1000，**跳过等于应收的和重复的**，取够 [max] 个为止。
///
/// 例：
/// - 应收 240 → `[240, 250, 300]`（正好 / 250 / 300）
/// - 应收 550 → `[550, 600, 1000]`
/// - 应收 61  → `[61, 70, 100]`
/// - 应收 245.5 → `[245.5, 250, 300]`
List<double> quickReceivedAmounts(double due, {int max = 3}) {
  final base = round2(due < 0 ? 0 : due);
  final out = <double>[base]; // 第一个 = 正好
  for (final step in const [10.0, 50.0, 100.0, 200.0, 500.0, 1000.0]) {
    if (out.length >= max) break;
    final up = round2((base / step).ceil() * step);
    if (up <= base + 0.001) continue; // 正好就是这个数，不必重复给
    if (out.any((v) => (v - up).abs() < 0.005)) continue; // 和已有的一样
    out.add(up);
  }
  return out;
}
