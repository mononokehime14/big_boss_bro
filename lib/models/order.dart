import '../utils/format.dart' show signedAmount;
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

/// 堂食 / 外卖 / 电话外卖 / 平台外卖。会打在小票和厨房单上。
///
/// - [dineIn]：堂食，有桌号；
/// - [takeaway]：到店买走的外卖（没桌号）；
/// - [phonecallTakeaway]：**打电话点的外卖**（也没桌号）——
///   跟 [takeaway] 一样不用桌号，但**标签、日结统计都单独一份**，方便老板看「电话单多少」；
/// - [platformTakeaway]：**平台外卖**（Uber Eats / DiDi Food 这类 App 来的单）——
///   **流程跟电话外卖完全一样**（不用桌号、能起名字、能填等待时间），区别只有两处：
///   1. **厨房单上不区分**：底部徽标和门牌都打「外卖」（厨师不用管平台还是电话）；
///   2. **日结分开算**：左侧单独一行「平台外卖」；右侧**平台收的刷卡**单独列
///      「平台刷卡」（平台收的现金照样并进「现金」）。
///
///   见 `services/sales_totals.dart` 和 `services/ticket_builder.dart`。
///
/// ⚠️ 枚举值的写法：**分号只写在最后一个值后面**（中间用逗号），
/// 写成 `takeaway('takeaway');` 再另起一行那个值，编译器就会报
/// 「Expected an identifier」/「Enums can't declare abstract members」。
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway'),
  phonecallTakeaway('phonecall_takeaway'),
  platformTakeaway('platform_takeaway');

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

  /// **选中的定制项：组名 → 选项值**（`{'Size': 'Grande'}`）。
  ///
  /// 为什么光有 [options] 还不够：[options] 里**只有值**（`Grande`），组名丢了 ——
  /// 而厨师单的「数量」列要认 **Size** 这一组、按老板的手写习惯换算
  /// （`Grande` → 份数、`Mediano` → 份数÷2、`Chico` → 圆圈里的份数，
  /// 见 `receipt_layout.dart` 的 `kitchenQtyShorthandLabel`）。
  ///
  /// - 普通多选项（Size: Grande）→ `{'Size': 'Grande'}`；
  /// - 加料开关（EXTRA BOBA 选了）→ `{'EXTRA BOBA': 'EXTRA BOBA'}`（值就是组名，
  ///   跟 [options] 一致）；
  /// - **老数据没有这个字段** → 空 map（厨师单照老规则打份数）。
  final Map<String, String> optionGroups;

  /// **特别备注**：可以好几条（点菜时一条一条加进来的）。
  final List<String> notes;

  /// 每条特别备注对应的**加价**（跟 [notes] 一一对应；短了按 0 算）。
  ///
  /// 为什么要有它：「换炒饭 +70」「不要炒饭 -60」这种备注是要**改钱的**。
  /// 加价按**每份**算（跟 [unitPrice] 一个口径），所以
  /// `小计 = (单价 + 备注加价合计) × 份数`。
  ///
  /// 老数据（JSON 里没有这个字段）→ 空列表，等价于"备注都不加钱"，行为不变。
  final List<double> notePrices;

  /// 菜价的单位（Excel 里的「单位」列，例如 份 / 杯）；空 = 不显示。
  final String unit;

  /// **菜品昵称**的快照（Excel 的「菜品昵称」列，例如 `L #1`）；空 = 没有昵称。
  ///
  /// - **点单界面 / 厨师单显示昵称**（员工看着顺口）；
  /// - **顾客小票打全名**（[name]）—— 客人看到的必须跟菜单一致。
  ///
  /// 在这里存**快照**（而不是打印时去查菜单）：菜单改了之后，老单子上的名字
  /// 也不应该跟着变（跟 [name] / [unitPrice] 一个道理）。
  final String nickName;

  /// 厨房**已经收到几份**（「厨房」按钮打成功之后把当时的份数记下来）。
  ///
  /// 为什么记"几份"而不是"打过没"：**同一道菜后来又加了一份**，现在会**并进这一行**
  /// （不再另起一行），份数从 1 变 2，而厨房手上还是 1 份 —— 厨房单只需要打**多出来的那份**。
  /// 见 `PosController.unsentLines()` / `OrderLine.unsentQty`。
  ///
  /// - `0` = 一份都没给厨房；
  /// - `>= quantity` = 厨房手上就是当前这个份数（这一行不用再打）。
  final int sentQty;

  /// 这一行**是不是已经全部下过厨房**（购物车里用绿色 / 黄色区分）。
  bool get sentToKitchen => quantity > 0 && sentQty >= quantity;

  /// **还要给厨房补几份**（0 = 不用再打；追单合并过的行只有多出来的那几份）。
  int get unsentQty => quantity > sentQty ? quantity - sentQty : 0;

  const OrderLine({
    required this.name,
    this.itemId = '',
    required this.quantity,
    required this.unitPrice,
    this.options = const [],
    this.optionGroups = const {},
    this.notes = const [],
    this.notePrices = const [],
    this.unit = '',
    this.nickName = '',
    this.sentQty = 0,
  });

  /// 所有备注拼成一行（**不带价格**；厨师单 / 打印用）。
  String get note => notes.join(' · ');

  /// 第 [i] 条备注的加价（越界 / 没填 = 0）。
  double notePriceAt(int i) => i < notePrices.length ? notePrices[i] : 0;

  /// 备注加价合计（**每份**）。
  double get notePriceTotal {
    var sum = 0.0;
    for (var i = 0; i < notes.length; i++) {
      sum += notePriceAt(i);
    }
    return round2(sum);
  }

  /// **实收单价** = 菜单单价 + 备注加价（「换炒饭 +70」就加在这里）。
  double get effectiveUnitPrice => round2(unitPrice + notePriceTotal);

  /// 第 [i] 条备注的显示文字：`换炒饭 +70` / `不要炒饭 -60`（加价 0 就只显示文字）。
  String noteLabelAt(int i) {
    final p = notePriceAt(i);
    return p == 0 ? notes[i] : '${notes[i]} ${signedAmount(p)}';
  }

  /// 所有备注的**带价签**文字（界面 / 顾客小票用）：`换炒饭 +70 · 少辣`。
  String get noteLabels {
    final out = <String>[];
    for (var i = 0; i < notes.length; i++) {
      out.add(noteLabelAt(i));
    }
    return out.join(' · ');
  }

  /// **员工看的那份名字**：有昵称就用昵称，没有就用全名。
  ///
  /// 用它的是：点单页购物车、厨师单。**顾客小票用 [name]**。
  String get displayName =>
      nickName.trim().isEmpty ? name : nickName.trim();

  /// 某个定制项组选了什么（`optionInGroup('Size')` → `Grande`；没选 = 空串）。
  ///
  /// 组名比对**不分大小写、忽略前后空格**（Excel 里写 `Size` / `size ` 都认）。
  /// 老数据没有 [optionGroups] → 一律返回空串（厨师单就照老规则打份数）。
  String optionInGroup(String group) {
    final want = group.trim().toLowerCase();
    for (final e in optionGroups.entries) {
      if (e.key.trim().toLowerCase() == want) return e.value;
    }
    return '';
  }

  /// 小计 = **实收单价**（含备注加价）× 份数。
  double get subtotal => round2(effectiveUnitPrice * quantity);

  /// 选项 + 备注（带价签）的简短描述（打在小票里菜名的下面）。
  String get detail {
    final parts = <String>[];
    if (options.isNotEmpty) parts.add(options.join(' / '));
    if (noteLabels.trim().isNotEmpty) parts.add(noteLabels.trim());
    return parts.join(' · ');
  }

  OrderLine copyWith({
    String? name,
    String? itemId,
    int? quantity,
    double? unitPrice,
    List<String>? options,
    Map<String, String>? optionGroups,
    List<String>? notes,
    String? unit,
    String? nickName,
    int? sentQty,
    List<double>? notePrices,
  }) =>
      OrderLine(
        name: name ?? this.name,
        itemId: itemId ?? this.itemId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        options: options ?? this.options,
        optionGroups: optionGroups ?? this.optionGroups,
        notes: notes ?? this.notes,
        notePrices: notePrices ?? this.notePrices,
        unit: unit ?? this.unit,
        nickName: nickName ?? this.nickName,
        sentQty: sentQty ?? this.sentQty,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'itemId': itemId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'options': options,
        // 组名 → 选项值（老数据没有 → 空 map；只用来给厨师单数量列换算）
        'optionGroups': optionGroups,
        'notes': notes,
        // 备注加价（跟 notes 一一对应；老数据没有 → 空 = 都不加钱）
        'notePrices': notePrices,
        'unit': unit,
        'nickName': nickName,
        // 厨房已经收到几份（老读者看 sentToKitchen 也一样能懂）
        'sentQty': sentQty,
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
        // 老数据没有 optionGroups → 空 map（厨师单数量列照老规则打）
        optionGroups: _optionGroupsFromJson(json),
        // 备注：新格式是数组；老数据是单个字符串（`note`）
        notes: _notesFromJson(json),
        notePrices: _notePricesFromJson(json),
        unit: (json['unit'] as String?) ?? '',
        // 老数据没有昵称 → 空 = 显示全名
        nickName: (json['nickName'] as String?) ?? '',
        // 老数据没有 sentQty：有 sentToKitchen 就按"整行都下过厨"算，
        // 老数据没有 sentToKitchen → 当作已经下过厨房（那时候下单一律打厨房单）
        sentQty: (json['sentQty'] as num?)?.toInt() ??
            (((json['sentToKitchen'] as bool?) ?? true)
                ? (json['quantity'] as num).toInt()
                : 0),
      );

  /// 「组名 → 选项值」：老数据没有这个字段 → 空 map；坏形状（不是 map）也当空。
  static Map<String, String> _optionGroupsFromJson(Map<String, dynamic> json) {
    final raw = json['optionGroups'];
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k == null || v == null) return;
      final key = k.toString().trim();
      if (key.isEmpty) return;
      out[key] = v.toString();
    });
    return out;
  }

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

  /// 备注加价：老数据没有这个字段 → 空（= 所有备注都不加钱）。
  static List<double> _notePricesFromJson(Map<String, dynamic> json) {
    final raw = json['notePrices'];
    if (raw is! List) return const [];
    return raw.map((e) => (e as num?)?.toDouble() ?? 0).toList();
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

  /// **外卖单的名字**（堂食恒为空）。
  ///
  /// 起名 = "保存这张外卖单"：起过名的外卖单会出现在桌号下拉的列表里，
  /// 可以随时选回来继续加菜/改单（见 `PosController.openTakeawayOrders`）；
  /// 结账后它就不再是"进行中"，自然从列表里消失。
  ///
  /// 空字符串 = 普通外卖单（每单独立、不列表，点完厨房直接结账就完事）。
  final String label;

  /// **当天第几号外卖**（外卖类型才有，1 开始；0 = 没有号，比如老数据）。
  ///
  /// 用来区分单子（外卖下拉列表 / 订单列表显示「外卖 #3」）；
  /// **厨房单上**：外卖单**没起名字**时打的就是这个号（`#3`，特大字）；
  /// 起过名字就打名字。见 `receipt_layout.dart` 的 `buildKitchenRows` ③段（"门牌"）。
  final int dailyNo;

  /// **要等多久（分钟）**：主要给**电话外卖**用 —— 客人在电话里说"20 分钟后来拿"，
  /// 保存这张单时填上，**厨房单会跟着打出来**（见 `receipt_layout.dart` 的 `buildKitchenRows`）。
  ///
  /// 0 = 没填（不打这一行）。
  final int waitMinutes;

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

  // ---- 分单（客人分开付钱时用）----

  /// **这张单是从哪张母单分出来的**（母单的 id）。
  ///
  /// - 空字符串 = 它自己就是**母单**（普通单，绝大多数情况）；
  /// - 非空 = 它是某张母单的**分单**：菜是从母单挪过来的，钱单独收，
  ///   名字显示成 `桌号 1-分单1`（见 `utils/order_label.dart`）。
  ///
  /// 母单**依旧存在**（至少留一道菜），分单结账不影响母单。
  final String parentId;

  /// **第几个分单**（1 起；0 = 不是分单）。
  ///
  /// 同一张母单下的分单从 1 开始编号，显示成 `-分单1` / `-分单2`。
  final int splitNo;

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
    this.label = '',
    this.dailyNo = 0,
    this.waitMinutes = 0,
    this.orderType = OrderType.dineIn,
    this.status = OrderStatus.inProgress,
    this.closedAt,
    this.currencyCode = '',
    this.exchangeRate = 0,
    this.receivedAmount,
    this.changeAmount,
    this.cashier = '',
    this.parentId = '',
    this.splitNo = 0,
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

  /// **不用桌号**的单：外卖 + 电话外卖 + 平台外卖。
  ///
  /// ⚠️ 注意写法：`orderType == OrderType.takeaway || OrderType.phonecallTakeaway`
  /// 这样写是错的 —— `||` 两边都要是 `bool`，右边那个是枚举值，编译器会报类型错。
  /// 正确写法是两边都做比较（下面这样）。
  bool get isTakeaway => orderType != OrderType.dineIn;

  /// **电话外卖**（打电话点的外卖）：跟外卖一样不用桌号，但统计单独算。
  bool get isPhoneTakeaway => orderType == OrderType.phonecallTakeaway;

  /// **平台外卖**（Uber / DiDi 这种 App 来的单）：
  /// 流程跟电话外卖一样，但**日结里单独一行**，刷卡还要单列「平台刷卡」
  /// （见 `services/sales_totals.dart`）。
  bool get isPlatformTakeaway => orderType == OrderType.platformTakeaway;

  /// 是不是**分单**（从母单分出来的一张单，单独收钱）。
  bool get isSplit => parentId.isNotEmpty;

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity);

  /// 外卖单在**界面**上用的标记：`名字 #号` / `名字` / `#号` / ''（老数据都没有）。
  ///
  /// 例：`张三 #3`、`#3`、`张三`。
  /// 厨房单上**只用其中一样**：有名字打名字，没名字才打 `#号`（见 `buildKitchenRows` ③段）。
  String get takeawayTag => <String>[
        if (label.trim().isNotEmpty) label.trim(),
        if (dailyNo > 0) '#$dailyNo',
      ].join(' ');

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
    String? label,
    int? dailyNo,
    int? waitMinutes,
    OrderType? orderType,
    OrderStatus? status,
    DateTime? closedAt,
    String? currencyCode,
    double? exchangeRate,
    double? receivedAmount,
    double? changeAmount,
    String? cashier,
    String? parentId,
    int? splitNo,
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
        label: label ?? this.label,
        dailyNo: dailyNo ?? this.dailyNo,
        waitMinutes: waitMinutes ?? this.waitMinutes,
        orderType: orderType ?? this.orderType,
        status: status ?? this.status,
        closedAt: closedAt ?? this.closedAt,
        currencyCode: currencyCode ?? this.currencyCode,
        exchangeRate: exchangeRate ?? this.exchangeRate,
        receivedAmount: receivedAmount ?? this.receivedAmount,
        changeAmount: changeAmount ?? this.changeAmount,
        cashier: cashier ?? this.cashier,
        parentId: parentId ?? this.parentId,
        splitNo: splitNo ?? this.splitNo,
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
        'label': label,
        'dailyNo': dailyNo,
        'waitMinutes': waitMinutes,
        'orderType': orderType.id,
        'status': status.id,
        'closedAt': closedAt?.toIso8601String(),
        'currencyCode': currencyCode,
        'exchangeRate': exchangeRate,
        'receivedAmount': receivedAmount,
        'changeAmount': changeAmount,
        'cashier': cashier,
        // 分单（老数据没有这两个字段 → 空 / 0，也就是"自己是母单"）
        'parentId': parentId,
        'splitNo': splitNo,
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
        // 旧数据没有这两个字段 → 空名字 / 0 号（显示时就不带「#N」）
        label: (json['label'] as String?) ?? '',
        dailyNo: (json['dailyNo'] as num?)?.toInt() ?? 0,
        waitMinutes: (json['waitMinutes'] as num?)?.toInt() ?? 0,
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
        // 老数据没有分单字段 → 当作"自己就是母单"
        parentId: (json['parentId'] as String?) ?? '',
        splitNo: (json['splitNo'] as num?)?.toInt() ?? 0,
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
