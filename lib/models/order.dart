/// 支付方式。
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

/// 订单里快照的一行（固化菜名/份数/单价/选项/备注，不依赖菜单，方便存历史）。
class OrderLine {
  final String name;
  final int quantity;
  final double unitPrice;

  /// 所选的定制项值，例如 ['Grande']。
  final List<String> options;

  /// 「其他备注」，例如“米饭替换成面条”。
  final String note;

  const OrderLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.options = const [],
    this.note = '',
  });

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
    int? quantity,
    double? unitPrice,
    List<String>? options,
    String? note,
  }) =>
      OrderLine(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        options: options ?? this.options,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'options': options,
        'note': note,
      };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        options:
            (json['options'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        note: (json['note'] as String?) ?? '',
      );
}

/// 一单订单（可能是“进行中”，也可能是“已结单”）。
class Order {
  final String id;
  final DateTime createdAt;
  final List<OrderLine> lines;
  final double total;

  /// 支付方式：进行中的单还没付钱，所以可以是 null。
  final PaymentMethod? paymentMethod;

  /// 桌号（餐厅自己定义，可为空）。
  final String table;

  final OrderStatus status;

  /// 结单时间（进行中时为 null）。
  final DateTime? closedAt;

  Order({
    required this.id,
    required this.createdAt,
    required this.lines,
    required this.total,
    this.paymentMethod,
    this.table = '',
    this.status = OrderStatus.inProgress,
    this.closedAt,
  });

  bool get isInProgress => status == OrderStatus.inProgress;

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity);

  Order copyWith({
    List<OrderLine>? lines,
    double? total,
    PaymentMethod? paymentMethod,
    String? table,
    OrderStatus? status,
    DateTime? closedAt,
  }) =>
      Order(
        id: id,
        createdAt: createdAt,
        lines: lines ?? this.lines,
        total: total ?? this.total,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        table: table ?? this.table,
        status: status ?? this.status,
        closedAt: closedAt ?? this.closedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'total': total,
        'paymentMethod': paymentMethod?.id,
        'table': table,
        'status': status.id,
        'closedAt': closedAt?.toIso8601String(),
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lines: (json['lines'] as List)
            .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] == null
            ? null
            : PaymentMethod.fromId(json['paymentMethod'] as String),
        table: (json['table'] as String?) ?? '',
        // 旧数据没有 status 字段：以前存的都是“已结单”
        status: json['status'] == null
            ? OrderStatus.completed
            : OrderStatus.fromId(json['status'] as String),
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.parse(json['closedAt'] as String),
      );
}
