import 'package:flutter_test/flutter_test.dart';

import 'package:big_boss_bro/data/settings_store.dart';
import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/escpos.dart';
import 'package:big_boss_bro/services/receipt_layout.dart';
import 'package:big_boss_bro/services/ticket_builder.dart';
import 'package:big_boss_bro/utils/format.dart';

ReceiptData _data({String paperWidth = '58'}) {
  return ReceiptData(
    storeName: '我的餐厅',
    headerLines: const ['Av. Reforma 123', 'Tel: 555-1234'],
    infoRows: const [
      ReceiptInfoRow('日期', '2026-01-01 12:30'),
      ReceiptInfoRow('单号', '20260101-001  桌号 8'),
      ReceiptInfoRow('收银员', 'ADMIN'),
    ],
    currency: '¥',
    paymentMethodLabel: '现金',
    lines: const [
      OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28, unit: '份'),
      OrderLine(name: '可乐', quantity: 1, unitPrice: 5),
    ],
    total: 61.0,
    thankyou: '谢谢光临',
    paperWidth: paperWidth,
    labels: const ReceiptLabels(
      labelTotal: '合计',
      labelPay: '支付方式',
    ),
  );
}

/// 是不是一条横线（`-----` / `=====`）。
bool _isDivider(String s) {
  final t = s.trim();
  return t.length >= 8 && RegExp(r'^[-=]+$').hasMatch(t);
}

void main() {
  group('money', () {
    test('加货币符号并保留两位', () {
      expect(money(28, '¥'), '¥28.00');
      expect(money(61.0, '¥'), '¥61.00');
      expect(money(5.5, '¥'), '¥5.50');
    });
  });

  group('中文宽度', () {
    test('中文按 2 列计', () {
      expect(displayWidth('牛肉炒饭'), 8);
      expect(displayWidth('ab'), 2);
      expect(displayWidth('可乐1'), 5);
    });

    test('padRight / padLeft / padCenter 使用显示宽度', () {
      expect(padRight('牛肉', 6), '牛肉  '); // 4 + 2
      expect(padLeft('¥9.00', 8).length, 8);
      expect(padCenter('餐厅', 8), '  餐厅  ');
    });
  });

  group('小票排版', () {
    test('58mm 每行不超过 32 列（不爆行）', () {
      final lines = buildReceiptLines(_data());
      for (final l in lines) {
        expect(displayWidth(l) <= 32, isTrue,
            reason: '行超宽: "$l" (${displayWidth(l)})');
      }
    });

    test('80mm 每行不超过 48 列', () {
      final lines = buildReceiptLines(_data(paperWidth: '80'));
      for (final l in lines) {
        expect(displayWidth(l) <= 48, isTrue);
      }
    });

    test('包含店名、店头信息、总金额、谢谢光临', () {
      final text = buildReceiptLines(_data()).join('\n');
      expect(text, contains('我的餐厅'));
      expect(text, contains('Av. Reforma 123'));
      expect(text, contains('¥61.00'));
      expect(text, contains('谢谢光临'));
      expect(text, contains('牛肉炒饭'));
    });

    test('单头是「标签: 值」左对齐（跟参考小票一样）', () {
      final lines = buildReceiptLines(_data());
      final info = lines.firstWhere((l) => l.startsWith('日期:'));
      expect(info, startsWith('日期:'));
      expect(info, contains('2026-01-01 12:30'));
      // 标签列对齐：值的起始列一样
      final a = lines.firstWhere((l) => l.startsWith('单号:'));
      expect(a.indexOf('20260101-001'), info.indexOf('2026-01-01 12:30'));
    });

    test('菜品两行式：菜名(+单位) 金额一行，下一行「数量 x 单价」', () {
      final lines = buildReceiptLines(_data());
      final nameLine = lines.firstWhere((l) => l.contains('牛肉炒饭'));
      expect(nameLine.trimRight(), endsWith('¥56.00')); // 28 × 2
      final qtyLine = lines[lines.indexOf(nameLine) + 1];
      expect(qtyLine, contains('2 份 x'));
      expect(qtyLine, contains('¥28.00'));
    });

    test('合计单独夹在两条横线中间', () {
      final lines = buildReceiptLines(_data());
      final i = lines.indexWhere((l) => l.trimLeft().startsWith('合计'));
      expect(i, greaterThan(0));
      expect(_isDivider(lines[i - 1]), isTrue);
      expect(_isDivider(lines[i + 1]), isTrue);
      expect(lines[i], contains('¥61.00'));
    });
  });

  group('小票：**合计那一行加大加粗**', () {
    List<TicketRow> rows({String paperWidth = '58'}) => buildReceiptRows(ReceiptData(
          storeName: '我的餐厅',
          currency: '¥',
          paymentMethodLabel: '现金',
          lines: const [OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28)],
          total: 61.0,
          thankyou: '谢谢光临',
          paperWidth: paperWidth,
          labels: const ReceiptLabels(labelTotal: '合计', labelPay: '支付方式'),
        ));

    test('合计行：**加粗 + 特大**，别的行还是正常字号', () {
      final all = rows();
      final total = all.firstWhere((r) => r.text.contains('合计'));
      expect(total.bold, isTrue, reason: '合计要加粗');
      expect(total.scale, TicketScale.xlarge, reason: '58mm 放得下「合计 ¥61.00」→ 特大');
      for (final r in all.where((r) => r != total && r.text.isNotEmpty)) {
        expect(r.scale, TicketScale.normal, reason: '只有合计行放大：${r.text}');
        expect(r.bold, isFalse, reason: '只有合计行加粗：${r.text}');
      }
    });

    test('合计行占满整行（特大 = 16 列，金额贴右边缘）', () {
      final total = rows().firstWhere((r) => r.text.contains('合计'));
      expect(displayWidth(total.text), 16);
      expect(total.text.trimLeft(), startsWith('合计'));
      expect(total.text.trimRight(), endsWith('¥61.00'));
    });

    test('标签太长放不下特大 → 自动退回「大」，一个字都不切', () {
      // 西语的「Importe adeudado」(16 列) + 金额(6 列) = 23 列 > 特大能用的 16 列
      final all = buildReceiptRows(ReceiptData(
        storeName: 'Tienda',
        currency: r'$',
        paymentMethodLabel: 'Efectivo',
        lines: const [OrderLine(name: 'Taco', quantity: 1, unitPrice: 61)],
        total: 61,
        thankyou: 'Gracias',
        paperWidth: '58',
        labels: const ReceiptLabels(
            labelTotal: 'Importe adeudado', labelPay: 'Pago'),
      ));
      final total = all.firstWhere((r) => r.text.contains('Importe adeudado'));
      expect(total.scale, TicketScale.large, reason: '放不下特大就退回「大」');
      expect(total.bold, isTrue);
      expect(displayWidth(total.text), 32, reason: '「大」还是整张纸宽（32 列）');
    });

    test('每一行都不超过**自己字号**的列数（58 / 80mm）', () {
      for (final paper in const ['58', '80']) {
        final paperCols = receiptColumns(paper);
        for (final r in rows(paperWidth: paper)) {
          expect(displayWidth(r.text) <= r.scale.columnsFor(paperCols), isTrue,
              reason: '${paper}mm 行超宽: "${r.text}" (${r.scale})');
        }
      }
    });
  });

  group('日期格式', () {
    test('中文用 年-月-日 24 小时', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 17, 5), 'zh'),
          '2026-09-20 17:05');
    });

    test('西语用 日/月/年 + a. m. / p. m.（跟参考小票一致）', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 5, 15), 'es'),
          '20/9/2026 5:15 a. m.');
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 17, 15), 'es'),
          '20/9/2026 5:15 p. m.');
    });

    test('英语用 AM / PM', () {
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 0, 0), 'en'),
          '20/9/2026 12:00 AM');
      expect(formatReceiptDateTime(DateTime(2026, 9, 20, 12, 0), 'en'),
          '20/9/2026 12:00 PM');
    });
  });

  group('单子类型（堂食 / 外卖 / 电话外卖）', () {
    Order orderWith(OrderType type) => Order(
          id: '20260920-001',
          createdAt: DateTime(2026, 9, 20, 17, 15),
          lines: const [
            OrderLine(name: 'VERDURA CANTONES', quantity: 1, unitPrice: 140),
          ],
          total: 140,
          orderType: type,
        );

    String receipt(OrderType type) => TicketBuilder.receiptLines(
          orderWith(type),
          Settings(),
        ).map((l) => l.text).join('\n');

    String kitchen(OrderType type) => TicketBuilder.kitchenLines(
          orderWith(type),
          Settings(),
        ).map((l) => l.text).join('\n');

    test('电话外卖的小票上打「电话外卖」，不会跟普通外卖混在一起', () {
      final t = receipt(OrderType.phonecallTakeaway);
      expect(t, contains('电话外卖'));
    });

    test('厨房单上也打「电话外卖」（厨房才知道这是电话来的单）', () {
      expect(kitchen(OrderType.phonecallTakeaway), contains('电话外卖'));
    });

    test('堂食 / 外卖 的老文案没变', () {
      expect(receipt(OrderType.dineIn), contains('堂食'));
      final takeaway = receipt(OrderType.takeaway);
      expect(takeaway, contains('外卖'));
      // 「外卖」是「电话外卖」的一部分，所以要另外确认没串台
      expect(takeaway, isNot(contains('电话外卖')));
    });
  });

  group('厨师单菜品行：**固定特大**（写死在代码里，没有设置项了）', () {
    KitchenData kitchen({String paperWidth = '58'}) => KitchenData(
          table: '8',
          orderId: '20260920-001',
          createdAt: DateTime(2026, 9, 20, 17, 15),
          lines: const [
            OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28, unit: '份'),
          ],
          paperWidth: paperWidth,
          labels: const KitchenLabels(
            title: '厨房单',
            labelTable: '桌号',
            colName: '菜名',
            colQty: '数量',
            append: '（追加）',
          ),
        );

    test('菜品行是特大，而且**占满**整行（58mm = 16 列）', () {
      // （以前列数被缩了两次 → 只剩 3 列可用，菜名被切成一两个字）
      final item =
          buildKitchenRows(kitchen()).firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(item.scale, TicketScale.xlarge);
      expect(item.scale, kKitchenItemScale);
      expect(displayWidth(item.text), 16);
    });

    test('菜品行列数 = 纸张列数的一半（58mm 16 列 / 80mm 24 列）', () {
      expect(kitchenItemColumns('58'), 16);
      expect(kitchenItemColumns('80'), 24);
      final item80 = buildKitchenRows(kitchen(paperWidth: '80'))
          .firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(item80.scale, TicketScale.xlarge);
      expect(displayWidth(item80.text), 24);
    });

    test('每一行都不超过**自己字号**的列数（58 / 80mm）', () {
      for (final paper in const ['58', '80']) {
        final paperCols = receiptColumns(paper);
        for (final r in buildKitchenRows(kitchen(paperWidth: paper))) {
          expect(displayWidth(r.text) <= r.scale.columnsFor(paperCols), isTrue,
              reason: '${paper}mm 行超宽: "${r.text}" (${r.scale})');
        }
      }
    });
  });

  group('厨师单菜品列：**数量在左、菜名居中**', () {
    KitchenData data({String paperWidth = '58'}) =>
        KitchenData(
          table: '8',
          orderId: '20260920-001',
          createdAt: DateTime(2026, 9, 20, 17, 15),
          // 两行的数量宽度不一样（`2 份` vs `12`），好验证菜名的位置
          lines: const [
            OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28, unit: '份'),
            OrderLine(name: '可乐', quantity: 12, unitPrice: 5),
          ],
          paperWidth: paperWidth,
          labels: const KitchenLabels(
            title: '厨房单',
            labelTable: '桌号',
            colName: '菜名',
            colQty: '数量',
            append: '（追加）',
          ),
        );

    List<String> lines({String paperWidth = '58'}) =>
        buildKitchenLines(data(paperWidth: paperWidth));

    List<TicketRow> rowsOf({String paperWidth = '58'}) =>
        buildKitchenRows(data(paperWidth: paperWidth));

    test('表头与菜品行都是「数量 菜名」', () {
      final l = lines();
      final header = l.firstWhere((x) => x.contains('菜名'));
      expect(header.trimLeft().startsWith('数量'), isTrue,
          reason: '表头应该是「数量 菜名」：$header');
      expect(header.indexOf('数量') < header.indexOf('菜名'), isTrue,
          reason: '数量必须排在菜名左边：$header');

      for (final name in const ['牛肉炒饭', '可乐']) {
        final row = l.firstWhere((x) => x.contains(name));
        expect(row.trimLeft().startsWith('数量'), isFalse);
        expect(row.indexOf(name) > 0, isTrue,
            reason: '$name 前面应该有数量：$row');
        // 数量在菜名**之前**：第一个非空格字符是数量（数字开头）
        expect(RegExp(r'^\s*\d').hasMatch(row), isTrue,
            reason: '数量应该在菜名左边：$row');
      }
      // 带单位的菜：数量列写「2 份」
      expect(l.any((x) => x.trimLeft().startsWith('2 份')), isTrue);
    });

    test('菜名在数量列右边**居中**（中心列对齐，不再挤在数量旁边）', () {
      final l = lines();
      final a = l.firstWhere((x) => x.contains('牛肉炒饭'));
      final b = l.firstWhere((x) => x.contains('可乐'));
      // 注意：要比的是**显示列数**（中文算 2 列），字符串下标在中文行上不等价
      double centerOf(String row, String name) =>
          displayWidth(row.substring(0, row.indexOf(name))) +
          displayWidth(name) / 2;
      expect((centerOf(a, '牛肉炒饭') - centerOf(b, '可乐')).abs() <= 1, isTrue,
          reason: '菜名居中的话，两行菜名的中心应该对齐：\n"$a"\n"$b"');
      // 短名字最能看出居中：`可乐` 前面应该有明显的留白（不是紧贴着数量列）
      final padBefore = displayWidth(b.substring(0, b.indexOf('可乐')));
      expect(padBefore, greaterThan(6),
          reason: '菜名应该居中（前面留白），而不是紧贴数量列：$b');
    });

    test('行不超宽（58/80mm 都不爆，按每行自己的字号算）', () {
      for (final paper in const ['58', '80']) {
        final paperCols = receiptColumns(paper);
        for (final r in rowsOf(paperWidth: paper)) {
          expect(displayWidth(r.text) <= r.scale.columnsFor(paperCols), isTrue,
              reason: '${paper}mm 行超宽: "${r.text}" (${r.scale})');
        }
      }
    });
  });

  group('厨师单顶部：**外卖的名字 / 号 + 等待时间都是特大字**', () {
    const labels = KitchenLabels(
      title: '厨师单',
      labelTable: '桌号',
      colName: '菜名',
      colQty: '数量',
      append: '（追加）',
      wait: '等待',
      minutes: '分钟',
    );

    KitchenData takeaway({
      String label = '',
      int dailyNo = 0,
      int waitMinutes = 0,
      bool phone = false,
    }) =>
        KitchenData(
          table: '', // 外卖没有桌号
          orderId: '20261011-003',
          createdAt: DateTime(2026, 10, 11, 13, 45),
          lines: const [
            OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28),
          ],
          paperWidth: '58',
          isTakeaway: true,
          orderLabel: label,
          dailyNo: dailyNo,
          waitMinutes: waitMinutes,
          typeLabel: phone ? '电话外卖' : '外卖',
          labels: labels,
        );

    TicketRow row(List<TicketRow> rows, String needle) =>
        rows.firstWhere((r) => r.text.contains(needle));

    test('外卖顶部：标题是「大」，「外卖 + 时间」和名字都是「特大」，名字在时间下面', () {
      final rows = buildKitchenRows(takeaway(label: '张三', dailyNo: 3));
      // 标题（分票编号）：只要「大」
      expect(row(rows, '厨师单').scale, TicketScale.large);
      // 「外卖 10-10 13:45」：票面上最大的一行
      final whereRow = row(rows, '外卖');
      expect(whereRow.scale, TicketScale.xlarge);
      expect(whereRow.text, contains('13:45'));
      // 名字：特大，而且排在「外卖 + 时间」**下面**
      final name = row(rows, '张三');
      expect(name.scale, TicketScale.xlarge);
      expect(name.text.trim(), '张三');
      expect(rows.indexOf(name), greaterThan(rows.indexOf(whereRow)),
          reason: '名字要排在「外卖 + 时间」后面：\n${rows.map((r) => r.text).join('\n')}');
    });

    test('外卖没名字：打系统给的号（#3），也是特大字', () {
      final rows = buildKitchenRows(takeaway(dailyNo: 3));
      final no = row(rows, '#3');
      expect(no.scale, TicketScale.xlarge);
      expect(no.text.trim(), '#3');
    });

    test('电话外卖：等待时间是特大字（厨房一眼看到）', () {
      final rows = buildKitchenRows(
          takeaway(label: '张三', waitMinutes: 20, phone: true));
      final wait = row(rows, '等待');
      expect(wait.text, contains('20'));
      expect(wait.scale, TicketScale.xlarge);
    });

    test('选项 + 备注：**一条一行**打全 —— 备注不再被截断', () {
      final rows = buildKitchenRows(KitchenData(
        table: '8',
        orderId: '20261011-005',
        createdAt: DateTime(2026, 10, 11, 13, 45),
        lines: const [
          OrderLine(
            name: '牛肉炒饭',
            quantity: 1,
            unitPrice: 28,
            options: ['Grande'],
            notes: ['不要香菜', '少放辣'],
          ),
        ],
        paperWidth: '58',
        // 菜品行固定特大（58mm = 16 列）—— 以前选项+备注挤一行会被切掉
        labels: labels,
      ));
      final text = rows.map((r) => r.text).join('\n');
      expect(text, contains('Grande'));
      expect(text, contains('不要香菜'), reason: '备注必须打出来（以前排在选项后面被 cut）');
      expect(text, contains('少放辣'));
      // 选项、每条备注各占一行
      expect(rows.where((r) => r.text.contains('Grande')).length, 1);
      expect(rows.where((r) => r.text.contains('不要香菜')).length, 1);
      expect(rows.where((r) => r.text.contains('少放辣')).length, 1);
    });

    test('超长备注：**折行**打全，不截断', () {
      // 40 个字 = 80 列 —— 58mm 一行只放得下 30 列，至少要折成 3 行
      final long = '不要香菜不要洋葱不要辣椒不要葱花不要蒜末不要柠檬不要冰不要糖不要盐不要醋';
      final rows = buildKitchenRows(KitchenData(
        table: '8',
        orderId: '20261011-006',
        createdAt: DateTime(2026, 10, 11, 13, 45),
        lines: [
          OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28, notes: [long]),
        ],
        paperWidth: '58',
        labels: labels,
      ));
      final noteRows = rows.where((r) => r.text.contains('不要')).toList();
      expect(noteRows.length, greaterThan(1), reason: '这么长应该折成好几行');
      for (final r in noteRows) {
        expect(displayWidth(r.text) <= 32, isTrue, reason: '行超宽: "${r.text}"');
      }
      // 去掉换行和缩进拼起来，应该能还原整条备注 —— 一个字都没丢
      final flat = rows.map((r) => r.text).join().replaceAll(' ', '');
      expect(flat, contains(long), reason: '折行之后内容必须一模一样，不能丢字');
    });

    test('没填等待时间就不打那一行', () {
      final rows = buildKitchenRows(takeaway(label: '张三', phone: true));
      expect(rows.any((r) => r.text.contains('等待')), isFalse);
    });

    test('堂食不打名字 / 号那行（有桌号就够了）', () {
      final rows = buildKitchenRows(KitchenData(
        table: '8',
        orderId: '20261011-004',
        createdAt: DateTime(2026, 10, 11, 13, 45),
        lines: const [OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28)],
        paperWidth: '58',
        typeLabel: '堂食',
        orderLabel: '张三', // 就算传了名字，堂食也不打这行
        dailyNo: 9,
        labels: labels,
      ));
      expect(rows.any((r) => r.text.contains('张三')), isFalse);
      expect(rows.any((r) => r.text.contains('#')), isFalse);
    });

    test('名字 / 等待时间再长也不爆行（特大 16 列）', () {
      final rows = buildKitchenRows(takeaway(
        label: '名字特别特别长的外卖客人',
        dailyNo: 3,
        waitMinutes: 120,
        phone: true,
      ));
      for (final r in rows) {
        expect(displayWidth(r.text) <= r.scale.columnsFor(32), isTrue,
            reason: '行超宽: "${r.text}" (${r.scale})');
      }
    });
  });

  group('菜品昵称：**厨师单用昵称、顾客小票用全名**', () {
    Order order({String nick = 'L #1'}) => Order(
          id: '20261011-007',
          createdAt: DateTime(2026, 10, 11, 13, 45),
          lines: [
            OrderLine(
              name: 'Chop Suey Pollo',
              nickName: nick,
              quantity: 1,
              unitPrice: 160,
            ),
          ],
          total: 160,
        );

    String kitchen({String nick = 'L #1'}) => TicketBuilder.kitchenLines(
          order(nick: nick),
          Settings(),
        ).map((l) => l.text).join('\n');

    String receipt({String nick = 'L #1'}) => TicketBuilder.receiptLines(
          order(nick: nick),
          Settings(),
        ).map((l) => l.text).join('\n');

    /// **去掉空白和换行**再比。
    ///
    /// 为什么：厨师单的菜品是**特大**字号，58mm 一行只有 16 列，
    /// 减去数量列 5 列，**菜名只剩 11 列** —— `Chop Suey Pollo`（15 列）放不下，
    /// 会按规则**折成两行**（优先在空格处断、整行居中）。折行不等于丢字，
    /// 所以这里把空白去掉再断言。
    String flat(String ticket) => ticket.replaceAll(RegExp(r'\s+'), '');

    test('厨房单打**昵称**', () {
      expect(flat(kitchen()), contains('L#1'));
      expect(kitchen(), isNot(contains('Chop Suey Pollo')),
          reason: '厨房单上不该出现全名（员工看昵称）');
    });

    test('顾客小票打**全名**，不出昵称', () {
      expect(receipt(), contains('Chop Suey Pollo'));
      expect(receipt(), isNot(contains('L #1')),
          reason: '纸是给客人的，名字必须跟菜单一致（全名）');
    });

    test('没昵称时两边都用全名（厨师单放不下会折行，不算错）', () {
      expect(flat(kitchen(nick: '')), contains('ChopSueyPollo'));
      expect(receipt(nick: ''), contains('Chop Suey Pollo'));
    });

    test('OrderLine.displayName：有昵称用昵称，没有用全名', () {
      expect(order().lines.first.displayName, 'L #1');
      expect(order(nick: '   ').lines.first.displayName, 'Chop Suey Pollo');
    });
  });
}
