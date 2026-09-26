import '../utils/pricing.dart';

/// 支付方式。
///
/// 注：[qr]（扫码）**已经不在收款界面上出现**（你要求去掉），
/// 保留这个值只是为了**老订单还能正确显示/统计**。
enum PaymentMethod {
  cash('cash'),
  card('card'),
  qr('qr');

  final String id;
  const PaymentMethod(this.id);

  static PaymentMethod fromId(String id) =>
      PaymentMethod.values.firstWhere((e) => e.id == id,
          orElse: () => PaymentMethod.cash);
}

/// 订单状态：进行中（已下单，还没结账）/ 已结单。
enum OrderStatus {
  inProgress('in_progress'),
  completed('completed');

  final String id;
  const OrderStatus(this.id);

  static OrderStatus fromId(String id) => OrderStatus.values.firstWhere(
        (e) => e.id == id,
        orElse: () => OrderStatus.completed,
      );
}

/// 堂食 / 外卖 / 电话外卖。会打在小票和厨房单上。
///
/// - [dineIn]：堂食，有桌号；
/// - [takeaway]：到店买走的外卖（没桌号）；
/// - [phonecallTakeaway]：**打电话点的外卖**（也没桌号）——
///   跟 [takeaway] 一样不用桌号，但**标签、日结统计都单独一份**，方便老板看「电话单多少」。
///
/// ⚠️ 枚举值的写法：**分号只写在最后一个值后面**（中间用逗号），
/// 写成 `takeaway('takeaway');` 再另起一行那个值，编译器就会报
/// 「Expected an identifier」/「Enums can't declare abstract members」。
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway'),
  phonecallTakeaway('phonecall_takeaway');

  final String id;
  const OrderType(this.id);

  static OrderType fromId(String id) => OrderType.values.firstWhere(
        (e) => e.id == id,
        orElse: () => OrderType.dineIn,
      );
}

/// 现金结账时可选收到的币种（这是开发侧默认清单：墨西哥比索 / 美元 / 人民币）。
const List<String> kCashCurrencies = ['MXN', 'USD', 'RMB'];

/// 币种 → 显示符号。
const Map<String, String> kCurrencySymbols = {
  'MXN': r'$',
  'USD': r'$',
  'RMB': '¥',
};

/// 订单里快照的一行（固化菜名/份数/单价/选项/备注，不依赖菜单，方便存历史）。
class OrderLine {
  final String name;

  /// 菜单里的菜品 id（用来查菜单、按新选项重算价格、统计流行度）。
  /// 老数据没有这个字段 → 空字符串，需要时按菜名去菜单里找。
  final String itemId;

  final int quantity;
  final double unitPrice;

  /// 所选的定制项值，例如 ['Grande']。
  final List<String> options;

  /// **特别备注**：可以好几条（点菜时一条一条加进来的）。
  final List<String> notes;

  /// 菜价的单位（Excel 里的「单位」列，例如 份 / 杯）；空 = 不显示。
  final String unit;

  /// 这一行**是否已经下过厨房**（= 已经打给厨房了）。
  ///
  /// 购物车下面两个按钮的区别就在这个字段：
  /// - **保存**：只把菜记到单上（`false`）—— 酒水、先垫着不下厨的菜就是这样，
  ///   购物车里用**橙色「未下厨」**标出来；
  /// - **厨房**：把这张单上**所有还没下厨的行**打一张厨房单，打成功后置为 `true`
  ///   （购物车里变成**绿色「已下厨」**）。
  ///
  /// 另外：**改动过的行会重新变回 `false`** —— 厨房收到的还是老版本，得再送一次。
  ///
  /// 老数据（JSON 里没有这个字段）默认 **true**：那时候下单一律会打厨房单。
  final bool sentToKitchen;

  const OrderLine({
    required this.name,
    this.itemId = '',
    required this.quantity,
    required this.unitPrice,
    this.options = const [],
    this.notes = const [],
    this.unit = '',
    this.sentToKitchen = false,
  });

  /// 所有备注拼成一行（显示 / 打印用）。
  String get note => notes.join(' · ');

  double get subtotal => unitPrice * quantity;

  /// 选项 + 备注的简短描述（打在小票里菜名的下面）。
  String get detail {
    final parts = <String>[];
    if (options.isNotEmpty) parts.add(options.join(' / '));
    if (note.trim().isNotEmpty) parts.add(note.trim());
    return parts.join(' · ');
  }

  OrderLine copyWith({
    String? name,
    String? itemId,
    int? quantity,
    double? unitPrice,
    List<String>? options,
    List<String>? notes,
    String? unit,
    bool? sentToKitchen,
  }) =>
      OrderLine(
        name: name ?? this.name,
        itemId: itemId ?? this.itemId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        options: options ?? this.options,
        notes: notes ?? this.notes,
        unit: unit ?? this.unit,
        sentToKitchen: sentToKitchen ?? this.sentToKitchen,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'itemId': itemId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'options': options,
        'notes': notes,
        'unit': unit,
        'sentToKitchen': sentToKitchen,
      };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        name: json['name'] as String,
        itemId: (json['itemId'] as String?) ?? '',
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        options:
            (json['options'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        // 备注：新格式是数组；老数据是单个字符串（`note`）
        notes: _notesFromJson(json),
        unit: (json['unit'] as String?) ?? '',
        // 老数据没有这个字段 → 当作「已经下过厨房」（那时候下单一律打厨房单）
        sentToKitchen: (json['sentToKitchen'] as bool?) ?? true,
      );

  static List<String> _notesFromJson(Map<String, dynamic> json) {
    final raw = json['notes'];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    final legacy = (json['note'] as String?) ?? '';
    return legacy.trim().isEmpty ? const [] : [legacy];
  }
}

/// 一次收款记录。
///
/// 现在**一单只有一条**（AA 分开付已按你的要求去掉）；
/// 保留成列表是为了兼容存过的老数据。
/// 现金那条会记下客人给了多少、找了多少。
class Payment {
  final PaymentMethod method;

  /// 收了多少钱 —— 注意这是**本位币**金额（= 订单应收），
  /// 外币收款时客人实际给的钱看 [received]。
  final double amount;

  /// 现金才有：客人付的币种（MXN / USD / RMB）。
  final String currencyCode;

  /// 现金才有：客人实际给了多少（**用 [currencyCode] 那个币种计**）。
  final double? received;

  /// 现金才有：找零（同 [currencyCode]）。
  final double? change;

  final DateTime paidAt;

  /// 备注（老数据的 AA 份数标签等）；新单为空。
  final String label;

  /// 经手人（账号显示名），日结/小票上要打。
  final String cashier;

  const Payment({
    required this.method,
    required this.amount,
    this.currencyCode = '',
    this.received,
    this.change,
    required this.paidAt,
    this.label = '',
    this.cashier = '',
  });

  bool get isCash => method == PaymentMethod.cash;

  Payment copyWith({
    PaymentMethod? method,
    double? amount,
    String? currencyCode,
    double? received,
    double? change,
    DateTime? paidAt,
    String? label,
    String? cashier,
  }) =>
      Payment(
        method: method ?? this.method,
        amount: amount ?? this.amount,
        currencyCode: currencyCode ?? this.currencyCode,
        received: received ?? this.received,
        change: change ?? this.change,
        paidAt: paidAt ?? this.paidAt,
        label: label ?? this.label,
        cashier: cashier ?? this.cashier,
      );

  Map<String, dynamic> toJson() => {
        'method': method.id,
        'amount': amount,
        'currencyCode': currencyCode,
        'received': received,
        'change': change,
        'paidAt': paidAt.toIso8601String(),
        'label': label,
        'cashier': cashier,
      };

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        method: PaymentMethod.fromId((json['method'] as String?) ?? 'cash'),
        amount: (json['amount'] as num).toDouble(),
        currencyCode: (json['currencyCode'] as String?) ?? '',
        received: (json['received'] as num?)?.toDouble(),
        change: (json['change'] as num?)?.toDouble(),
        paidAt: json['paidAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['paidAt'] as String),
        label: (json['label'] as String?) ?? '',
        cashier: (json['cashier'] as String?) ?? '',
      );
}

/// 一单订单（可能是“进行中”，也可能是“已结单”）。
class Order {
  final String id;
  final DateTime createdAt;
  final List<OrderLine> lines;

  /// 最终应收（= 小计 - 折扣 + 另加的税）。下单时就写好，结账打折后再更新。
  final double total;

  // ---- 折扣（结账时设）----

  final DiscountType discountType;
  final double discountValue;

  // ---- 税（下单时从设置里快照下来，之后改设置不影响老单）----

  final double taxRate;
  final bool taxIncluded;

  // ---- 收款 ----

  /// 收款记录（现在一单一条；老数据里的多条也能读回来）。
  final List<Payment> payments;

  /// 支付方式：进行中的单还没付钱，所以可以是 null。
  final PaymentMethod? paymentMethod;

  /// 桌号（餐厅自己定义，可为空；外卖为空）。
  final String table;

  /// 堂食 / 外卖。
  final OrderType orderType;

  final OrderStatus status;

  /// 结单时间（进行中时为 null）。
  final DateTime? closedAt;

  /// 现金结账时收到的币种（MXN / USD / RMB）。
  final String currencyCode;

  /// 收款时用的汇率：**1 个 [currencyCode] = 多少本位币**。
  /// **0 = 用店里的货币收的，不需要换算**（本位币单就是这样）。
  final double exchangeRate;

  /// 现金结账时客人实际给了多少（用 [currencyCode] 那个币种计）。
  final double? receivedAmount;

  /// 找零 = 实收 - 应收（同 [currencyCode]）。
  final double? changeAmount;

  /// 开单的收银员（账号显示名）。
  final String cashier;

  // ---- 后台同步（Supabase）用的字段 ----

  /// **本地**最后一次改动的时间（离线也有意义；每次改单都会刷新）。
  final DateTime updatedAt;

  /// 服务器上的**版本号**（0 = 这张单还没推上去过）。
  /// 拉回来的数据 rev 更大 → 说明服务器那份更新，采纳它。
  final int rev;

  /// 最后改这张单的设备名（设置里填的「设备名」）。
  final String deviceId;

  /// **只在本地有意义**：有没有还没推上去的改动（推成功后置 false）。
  final bool dirty;

  Order({
    required this.id,
    required this.createdAt,
    required this.lines,
    required this.total,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.taxRate = 0,
    this.taxIncluded = true,
    List<Payment>? payments,
    this.paymentMethod,
    this.table = '',
    this.orderType = OrderType.dineIn,
    this.status = OrderStatus.inProgress,
    this.closedAt,
    this.currencyCode = '',
    this.exchangeRate = 0,
    this.receivedAmount,
    this.changeAmount,
    this.cashier = '',
    DateTime? updatedAt,
    this.rev = 0,
    this.deviceId = '',
    this.dirty = true,
    // 注意：updatedAt 是参数名，下面初始化列表里右边的 updatedAt 指的是这个参数
  })  : payments = payments ?? <Payment>[],
        updatedAt = updatedAt ?? createdAt;

  /// 改这张单时统一走它：刷新本地时间、标脏（要重新推给后台）。
  ///
  /// [deviceId] 传当前设备名（设置里那个）；不传就保留原来的。
  Order touch({String? deviceId}) => copyWith(
        updatedAt: DateTime.now(),
        deviceId: (deviceId == null || deviceId.isEmpty) ? null : deviceId,
        dirty: true,
      );

  bool get isInProgress => status == OrderStatus.inProgress;

  /// **不用桌号**的单：外卖 + 电话外卖。
  ///
  /// ⚠️ 注意写法：`orderType == OrderType.takeaway || OrderType.phonecallTakeaway`
  /// 这样写是错的 —— `||` 两边都要是 `bool`，右边那个是枚举值，编译器会报类型错。
  /// 正确写法是两边都做比较（下面这样）。
  bool get isTakeaway => orderType != OrderType.dineIn;

  /// **电话外卖**（打电话点的外卖）：跟外卖一样不用桌号，但统计单独算。
  bool get isPhoneTakeaway => orderType == OrderType.phonecallTakeaway;

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity);

  /// 小计（所有菜相加，**不含**折扣和另加的税）。
  double get subtotal =>
      round2(lines.fold<double>(0, (sum, l) => sum + l.subtotal));

  /// 用订单自己记的折扣/税算出金额明细。
  PriceBreakdown get price => PriceBreakdown.of(
        subtotal: subtotal,
        discountType: discountType,
        discountValue: discountValue,
        taxRate: taxRate,
        taxIncluded: taxIncluded,
      );

  double get discountAmount => price.discount;
  double get taxAmount => price.tax;

  /// 按当前明细重算应收（打折、追单后都要重算）。
  double get computedTotal => price.total;

  /// 用某个币种收款时，**这个币种**的应收（汇率 0 = 本币，直接返回总额）。
  double foreignDue(double rate) => toForeign(total, rate);

  /// 收了多少（本位币）。
  double get paidAmount =>
      round2(payments.fold<double>(0, (sum, p) => sum + p.amount));

  /// 还差多少（可能是 0）。
  double get remaining {
    final r = round2(total - paidAmount);
    return r < 0 ? 0 : r;
  }

  /// 已收够了（允许 1 分钱的浮点误差）。
  bool get isFullyPaid => total - paidAmount <= 0.005;

  /// 收款用的币种是不是**外币**（需要打汇率那种）。
  /// 本位币收款时 [exchangeRate] 是 0，所以这里为 false。
  bool get isForeignCurrency => currencyCode.isNotEmpty && exchangeRate > 0;

  /// 用来统计的收款记录：正常就是 [payments]；
  /// 万一遇到「有支付方式但没有收款记录」的单（老数据/手工构造），
  /// 就补一条，保证日结的支付方式合计不会漏账。
  List<Payment> get effectivePayments {
    if (payments.isNotEmpty) return payments;
    final m = paymentMethod;
    if (m == null) return const <Payment>[];
    return [
      Payment(
        method: m,
        amount: total,
        currencyCode: currencyCode,
        received: receivedAmount,
        change: changeAmount,
        paidAt: closedAt ?? createdAt,
        cashier: cashier,
      ),
    ];
  }

  /// 折扣的显示文字，例如「-10%」/「-20.00」。没折扣返回空串。
  String discountLabel(String currency) {
    switch (discountType) {
      case DiscountType.none:
        return '';
      case DiscountType.percent:
        final v = discountValue;
        final txt = v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(2);
        return '-$txt%';
      case DiscountType.amount:
        return '-$currency${discountValue.toStringAsFixed(2)}';
    }
  }

  Order copyWith({
    List<OrderLine>? lines,
    double? total,
    DiscountType? discountType,
    double? discountValue,
    double? taxRate,
    bool? taxIncluded,
    List<Payment>? payments,
    PaymentMethod? paymentMethod,
    String? table,
    OrderType? orderType,
    OrderStatus? status,
    DateTime? closedAt,
    String? currencyCode,
    double? exchangeRate,
    double? receivedAmount,
    double? changeAmount,
    String? cashier,
    DateTime? updatedAt,
    int? rev,
    String? deviceId,
    bool? dirty,
  }) =>
      Order(
        id: id,
        createdAt: createdAt,
        lines: lines ?? this.lines,
        total: total ?? this.total,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        taxRate: taxRate ?? this.taxRate,
        taxIncluded: taxIncluded ?? this.taxIncluded,
        payments: payments ?? this.payments,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        table: table ?? this.table,
        orderType: orderType ?? this.orderType,
        status: status ?? this.status,
        closedAt: closedAt ?? this.closedAt,
        currencyCode: currencyCode ?? this.currencyCode,
        exchangeRate: exchangeRate ?? this.exchangeRate,
        receivedAmount: receivedAmount ?? this.receivedAmount,
        changeAmount: changeAmount ?? this.changeAmount,
        cashier: cashier ?? this.cashier,
        updatedAt: updatedAt ?? this.updatedAt,
        rev: rev ?? this.rev,
        deviceId: deviceId ?? this.deviceId,
        dirty: dirty ?? this.dirty,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'total': total,
        'discountType': discountType.id,
        'discountValue': discountValue,
        'taxRate': taxRate,
        'taxIncluded': taxIncluded,
        'payments': payments.map((p) => p.toJson()).toList(),
        'paymentMethod': paymentMethod?.id,
        'table': table,
        'orderType': orderType.id,
        'status': status.id,
        'closedAt': closedAt?.toIso8601String(),
        'currencyCode': currencyCode,
        'exchangeRate': exchangeRate,
        'receivedAmount': receivedAmount,
        'changeAmount': changeAmount,
        'cashier': cashier,
        // 后台同步用（服务器还会自己维护 rev / updated_at，本地这两个是缓存）
        'updatedAt': updatedAt.toIso8601String(),
        'rev': rev,
        'deviceId': deviceId,
        'dirty': dirty,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lines: (json['lines'] as List)
            .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num).toDouble(),
        discountType: DiscountType.fromId(json['discountType'] as String?),
        discountValue: (json['discountValue'] as num?)?.toDouble() ?? 0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
        taxIncluded: (json['taxIncluded'] as bool?) ?? true,
        // 旧数据没有 payments：把「一次付清」的旧字段补成一条收款记录，
        // 这样日结/按支付方式统计对老单也一样能算对。
        payments: _paymentsFromJson(json),
        paymentMethod: json['paymentMethod'] == null
            ? null
            : PaymentMethod.fromId(json['paymentMethod'] as String),
        table: (json['table'] as String?) ?? '',
        orderType: json['orderType'] == null
            ? OrderType.dineIn
            : OrderType.fromId(json['orderType'] as String),
        // 旧数据没有 status 字段：以前存的都是“已结单”
        status: json['status'] == null
            ? OrderStatus.completed
            : OrderStatus.fromId(json['status'] as String),
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.parse(json['closedAt'] as String),
        currencyCode: (json['currencyCode'] as String?) ?? '',
        exchangeRate: (json['exchangeRate'] as num?)?.toDouble() ?? 0,
        receivedAmount: (json['receivedAmount'] as num?)?.toDouble(),
        changeAmount: (json['changeAmount'] as num?)?.toDouble(),
        cashier: (json['cashier'] as String?) ?? '',
        // 老数据没有这几个同步字段：updatedAt 用 createdAt 顶，
        // rev=0 + dirty=true 表示「还没推上去」→ 第一次同步会把它推给后台。
        updatedAt: json['updatedAt'] == null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.parse(json['updatedAt'] as String),
        rev: (json['rev'] as num?)?.toInt() ?? 0,
        deviceId: (json['deviceId'] as String?) ?? '',
        dirty: (json['dirty'] as bool?) ?? true,
      );

  static List<Payment> _paymentsFromJson(Map<String, dynamic> json) {
    final raw = json['payments'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Payment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    // 老单：有支付方式就当作「一次付清」，金额取订单总额
    if (json['paymentMethod'] == null) return <Payment>[];
    return [
      Payment(
        method: PaymentMethod.fromId(json['paymentMethod'] as String),
        amount: (json['total'] as num).toDouble(),
        currencyCode: (json['currencyCode'] as String?) ?? '',
        received: (json['receivedAmount'] as num?)?.toDouble(),
        change: (json['changeAmount'] as num?)?.toDouble(),
        paidAt: json['closedAt'] == null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.parse(json['closedAt'] as String),
        cashier: (json['cashier'] as String?) ?? '',
      ),
    ];
  }
}
