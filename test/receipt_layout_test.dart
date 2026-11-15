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

/// 在一串字节里找一段子序列的位置（找不到 = -1）。
///
/// 用来验证「强制中文模式」那行真的带上了 `FS &`（`1C 26`）和 `FS .`（`1C 2E`）。
int _indexOfSeq(List<int> bytes, List<int> seq) {
  for (var i = 0; i + seq.length <= bytes.length; i++) {
    var ok = true;
    for (var j = 0; j < seq.length; j++) {
      if (bytes[i + j] != seq[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
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

  group('单子类型（堂食 / 外卖 / 电话外卖 / 平台外卖）', () {
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

    // 平台外卖（Uber / DiDi 这种 App 来的）：
    // - **顾客小票**上照实写「平台外卖」（这是正式叫法，跟日结对得上）；
    // - **厨房单不区分**：底部徽标和门牌都只打「外卖」（老板的要求：厨师不用管哪个平台）。
    test('平台外卖：小票打「平台外卖」，厨房单只打「外卖」（不额外区分）', () {
      final t = receipt(OrderType.platformTakeaway);
      expect(t, contains('平台外卖'));

      final k = kitchen(OrderType.platformTakeaway);
      expect(k, isNot(contains('平台外卖')),
          reason: '厨房单上不该出现「平台外卖」这几个字');
      expect(k, contains('外卖'), reason: '底部徽标要打「外卖」');

      // 跟普通外卖的厨房单**一模一样**（门牌 + 徽标都不区分）
      expect(kitchen(OrderType.platformTakeaway),
          kitchen(OrderType.takeaway));
    });

    test('平台外卖：带名字 / 等待时间时，厨房单照样打名字 + 等待分钟', () {
      final o = Order(
        id: '20261018-009',
        createdAt: DateTime(2026, 10, 18, 19, 30),
        lines: const [
          OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28),
        ],
        total: 28,
        orderType: OrderType.platformTakeaway,
        label: 'Uber 张三',
        waitMinutes: 20,
      );
      final lines = TicketBuilder.kitchenLines(o, Settings())
          .map((l) => l.text)
          .join('\n');
      expect(lines, contains('外卖 Uber 张三'));
      expect(lines, contains('等待 20 分钟'));
    });

    test('堂食 / 外卖 的老文案没变', () {
      expect(receipt(OrderType.dineIn), contains('堂食'));
      final takeaway = receipt(OrderType.takeaway);
      expect(takeaway, contains('外卖'));
      // 「外卖」是「电话外卖」的一部分，所以要另外确认没串台
      expect(takeaway, isNot(contains('电话外卖')));
    });

    test('厨房单底部：**即使票面语言是西语 / 英语，也照样打中文那行**', () {
      // 店里有中国厨师 —— 中文徽标是"固定要有"的，跟小票语言无关
      for (final lang in const ['es', 'en', 'zh']) {
        final s = Settings()..receiptLang = lang;
        final text = TicketBuilder.kitchenLines(orderWith(OrderType.takeaway), s)
            .map((l) => l.text)
            .join('\n');
        expect(text, contains('外卖'), reason: '语言=$lang 时中文徽标丢了');
      }
      // 西语票面：西文是 LLEVAR、中文是 外卖，两行都在
      final es = Settings()..receiptLang = 'es';
      final lines = TicketBuilder.kitchenLines(
              orderWith(OrderType.takeaway), es)
          .map((l) => l.text)
          .toList();
      expect(lines.any((l) => l.contains('LLEVAR')), isTrue);
      expect(lines.any((l) => l.contains('外卖')), isTrue);
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

  group('厨师单菜品列：**数量 + 两格 + 菜名（左对齐）**', () {
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
            colNote: '备注',
            append: '（追加）',
          ),
        );

    List<String> lines({String paperWidth = '58'}) =>
        buildKitchenLines(data(paperWidth: paperWidth));

    List<TicketRow> rowsOf({String paperWidth = '58'}) =>
        buildKitchenRows(data(paperWidth: paperWidth));

    test('不再打「数量 菜名」表头（Cant. / Producto 已取消）', () {
      final l = lines();
      expect(l.any((x) => x.contains('数量') && x.contains('菜名')), isFalse,
          reason: '表头整行已经取消：\n${l.join('\n')}');

      for (final name in const ['牛肉炒饭', '可乐']) {
        final row = l.firstWhere((x) => x.contains(name));
        expect(row.indexOf(name) > 0, isTrue,
            reason: '$name 前面应该有数量：$row');
        expect(RegExp(r'^\s*\d').hasMatch(row), isTrue,
            reason: '数量应该在菜名左边：$row');
      }
      expect(l.any((x) => x.trimLeft().startsWith('2 份')), isTrue);
    });

    test('菜名从固定第 6 格开始（数量列固定 5 格）', () {
      final l = lines();
      for (final name in const ['牛肉炒饭', '可乐']) {
        final row = l.firstWhere((x) => x.contains(name));
        final before = row.substring(0, row.indexOf(name));
        // 菜品行是特大字：数量列固定 5 个显示列，菜名从第 6 列开始。
        expect(displayWidth(before), 5,
            reason: '所有菜名应该从同一列开始：\n"$row"');
      }
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

  group('厨师单新版式：**别针区 → 编号 → 时间 → 门牌 → 菜品 → 底部徽标**', () {
    const labels = KitchenLabels(
      title: '厨师单',
      labelTable: '桌号',
      colName: '菜名',
      colQty: '数量',
      colNote: '备注',
      append: '（追加）',
      wait: '等待',
      minutes: '分钟',
    );

    KitchenData ticket({
      String table = '8',
      bool takeaway = false,
      String label = '',
      int dailyNo = 0,
      int waitMinutes = 0,
      String type = '',
      String western = 'AQUI',
      String chinese = '堂食',
      List<OrderLine> lines = const [
        OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28),
      ],
      String paperWidth = '58',
      int copyIndex = 1,
      int copyTotal = 1,
    }) =>
        KitchenData(
          table: table,
          orderId: '20261011-003',
          createdAt: DateTime(2026, 10, 11, 13, 45),
          lines: lines,
          paperWidth: paperWidth,
          copyIndex: copyIndex,
          copyTotal: copyTotal,
          isTakeaway: takeaway,
          orderLabel: label,
          dailyNo: dailyNo,
          waitMinutes: waitMinutes,
          // 门牌那行用的类型叫法（外卖打「外卖 张三」）
          typeLabel: type,
          badgeWestern: western,
          badgeChinese: chinese,
          labels: labels,
        );

    /// **最后一条虚线之后**就是票面最下面那块徽标。
    ///
    /// ⚠️ 厨师单的虚线是 `- - - -`（**中间有空格**），所以不能用 `_isDivider()`
    /// （那个是给小票的实线 `--------` 用的）。
    bool isDashRow(TicketRow r) {
      final plain = r.text.replaceAll('◆', '').replaceAll('#', '').trim();
      return r.scale == TicketScale.normal &&
          plain.isNotEmpty &&
          plain.runes.every((c) => c == 0x2D || c == 0x20); // 只有 '-' 和空格
    }

    List<TicketRow> badgeOf(KitchenData k) {
      final framed = !k.isTakeaway && k.paperWidth == '80';
      var rows = buildKitchenRows(k, frame: framed);
      if (framed) {
        rows = addDineInSidePattern(rows,
            contentCols: receiptColumns('80') - 12);
      }
      final last = rows.lastIndexWhere(isDashRow);
      expect(last, greaterThan(0), reason: '菜品区后面应该有一条虚线');
      return rows.sublist(last + 1);
    }

    test('① 最上面留 1 行（别针区），然后是「厨师单 1」（大）+ 时间（大）', () {
      final rows = buildKitchenRows(ticket(copyIndex: 1, copyTotal: 2));
      expect(kKitchenTopBlankRows, 1, reason: '厨师要把单子别在杆子上，顶上空 1 行');
      for (var i = 0; i < kKitchenTopBlankRows; i++) {
        expect(rows[i].text.trim(), isEmpty, reason: '第 ${i + 1} 行该是留白（别针区）');
      }
      final title = rows[kKitchenTopBlankRows];
      expect(title.text.trim(), '厨师单 1');
      expect(title.scale, kKitchenTitleScale);
      final time = rows[kKitchenTopBlankRows + 1];
      // ⚠️ 厨师单的时间是 `MM-DD HH:MM`；样本单是 2026-10-11 13:45 → `10-11 13:45`
      expect(time.text.trim(), '10-11 13:45');
      expect(time.scale, kKitchenTimeScale);
      expect(displayWidth(time.text), time.scale.columnsFor(32),
          reason: '时间那行占满整行（居中）');
    });

    test('②a 堂食左右边纹：80mm 下每行左右加 ◆', () {
      final dine = addDineInSidePattern(
          buildKitchenRows(ticket(paperWidth: '80'), frame: true),
          contentCols: receiptColumns('80') - 12);
      final item = dine.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(item.text.startsWith('◆'), isTrue,
          reason: '左边纹：${item.text}');
      expect(item.text.trimRight().endsWith('◆'), isTrue,
          reason: '右边纹：${item.text}');
      expect(item.raw, isNotNull, reason: '边纹要走原始字节（◆ 强制 GBK）');
    });

    test('② 门牌**紧跟时间**（中间不空行）；堂食门牌 = AQUI + 堂食 + 桌号（超大）', () {
      final rows = buildKitchenRows(ticket());
      final time = rows.indexWhere((r) => r.text.contains('13:45'));
      // 票面上半截要短：时间下面直接就是门牌，不空行
      final who = rows[time + 1];
      expect(who.text.trim(), 'AQUI 堂食 桌号 8',
          reason: '时间下面应该紧接着就是门牌：\n${rows.map((r) => r.text).join('\n')}');
      expect(who.scale, TicketScale.huge, reason: '堂食门牌要超大');
      final left = displayWidth(who.text) - displayWidth(who.text.trimLeft());
      final right = displayWidth(who.text) - displayWidth(who.text.trimRight());
      expect((left - right).abs() <= 1, isTrue, reason: '应该居中："${who.text}"');
      // 门牌下面才空一行（跟虚线分块）
      expect(rows[time + 2].text.trim(), isEmpty, reason: '门牌下面是空行');
    });

    test('③ 外卖门牌 = 「外卖 + 名字」；没名字就是「外卖 #3」（都是特大）', () {
      final named = buildKitchenRows(ticket(
        table: '', // 外卖没有桌号
        takeaway: true,
        label: '张三',
        type: '外卖',
        western: 'LLEVAR',
        chinese: '外卖',
      ));
      final name = named.firstWhere((r) => r.text.contains('张三'));
      expect(name.scale, kKitchenWhoScale);
      expect(name.text.trim(), '外卖 张三', reason: '外卖要把类型一起打出来');

      final noName = buildKitchenRows(ticket(
        table: '',
        takeaway: true,
        dailyNo: 3,
        type: '外卖',
        chinese: '外卖',
      ));
      final no = noName.firstWhere((r) => r.text.contains('#3'));
      expect(no.scale, kKitchenWhoScale);
      expect(no.text.trim(), '外卖 #3');
      expect(noName.any((r) => r.text.contains('桌号')), isFalse,
          reason: '外卖不该打桌号');
    });

    test('④ 电话外卖：等待时间跟门牌同档（特大）；没填就不打', () {
      final withWait = buildKitchenRows(ticket(
          table: '', takeaway: true, label: '张三', waitMinutes: 20));
      final wait = withWait.firstWhere((r) => r.text.contains('等待'));
      expect(wait.text.trim(), '等待 20 分钟');
      expect(wait.scale, kKitchenWhoScale);

      final noWait =
          buildKitchenRows(ticket(table: '', takeaway: true, label: '张三'));
      expect(noWait.any((r) => r.text.contains('等待')), isFalse);
    });

    test('⑤ 底部徽标：空行 → 一行「AQUI 堂食」，最大字号', () {
      final badge = badgeOf(ticket());
      expect(badge.first.text.trim(), isEmpty, reason: '徽标前面空一行');
      expect(badge.length, 2,
          reason: '徽标 = 空行 + 一行合并的 AQUI 堂食：\n${badge.map((r) => r.text).join('\n')}');
      final line = badge[1];
      expect(line.text, contains('AQUI'));
      expect(line.text, contains('堂食'));
      // 58mm 不套边纹；80mm 才套（见 ②a）
      expect(line.scale, kKitchenBadgeScale, reason: '徽标要最大');
      expect(line.bold, isTrue);
      // 徽标是票面**最后**的内容（切纸前那一块，插在杆上正好露出来）
      expect(badge.last.text, contains('堂食'));
    });

    test('⑥ 徽标合并成一行；外卖是「LLEVAR 外卖」，不再分两行', () {
      for (final takeaway in [false, true]) {
        final badge = badgeOf(ticket(
          table: takeaway ? '' : '8',
          takeaway: takeaway,
          western: takeaway ? 'LLEVAR' : 'AQUI',
          chinese: takeaway ? '外卖' : '堂食',
        ));
        expect(badge.length, 2);
        // 没有 `|` `_` `/` 这些老 ASCII 图案
        for (final r in badge.skip(1)) {
          expect(RegExp(r'[<>|_/\\]').hasMatch(r.text), isFalse,
              reason: '徽标里不该再有 ASCII 图案字符："${r.text}"');
        }
      }
      final takeaway = badgeOf(ticket(
          table: '', takeaway: true, western: 'LLEVAR', chinese: '外卖'));
      expect(takeaway[1].text, contains('LLEVAR'));
      expect(takeaway[1].text, contains('外卖'));
      expect(takeaway[1].text, isNot(contains('◆')),
          reason: '边纹只给堂食单');
    });

    test('⑦ 中文徽标**强制中文模式**打（整张票设 cp850 也不会变成 `?`）', () {
      final badge = badgeOf(ticket());
      final chinese = badge[1];
      expect(chinese.text, contains('堂食'));
      // 关键：中文行是**原始字节行**（自带 FS & … FS .），不看当前编码设置
      expect(chinese.raw, isNotNull,
          reason: '中文徽标要走 gbkLineBytes（自己进出中文模式），否则 cp850 下会变 `?`');
      final raw = chinese.raw!.toList();
      expect(_indexOfSeq(raw, const [0x1C, 0x26]), greaterThanOrEqualTo(0),
          reason: '缺 FS &（进中文模式）');
      expect(_indexOfSeq(raw, const [0x1C, 0x2E]), greaterThanOrEqualTo(0),
          reason: '缺 FS .（退出中文模式）');

      // 传空 = 只留西文（堂食仍有边纹）
      final none = badgeOf(ticket(chinese: ''));
      expect(none.any((r) => r.text.contains('堂食')), isFalse);
      expect(none.any((r) => r.text.contains('AQUI')), isTrue,
          reason: '西文照打');
    });

    test('⑦b 底部徽标：**加粗** + 比菜品再高一档（huge = 2 倍宽 / 3 倍高）', () {
      final badge = badgeOf(ticket());
      final line = badge[1];

      expect(line.scale, TicketScale.huge, reason: '徽标用最高一档字号');
      expect(kKitchenBadgeScale, TicketScale.huge,
          reason: '这个常量就是徽标的字号，改它就能整体升降档');
      // GS ! 的参数：宽 2 倍（高位 1）、高 3 倍（低位 2）→ 0x12
      expect(TicketScale.huge.gsBangParam, 0x12);

      expect(line.bold, isTrue, reason: '徽标要加粗');
      // 中文行走原始字节 → 加粗的 ESC E 1 / ESC E 0 要编进 raw 里
      final raw = line.raw!.toList();
      expect(_indexOfSeq(raw, const [0x1B, 0x45, 0x01]), greaterThanOrEqualTo(0),
          reason: '中文徽标缺 ESC E 1（加粗）');
      expect(_indexOfSeq(raw, const [0x1B, 0x45, 0x00]), greaterThanOrEqualTo(0),
          reason: '打完要取消加粗，否则后面全变粗');
    });

    test('⑧ 菜品之间空一行（一道菜一块，扫的时候不会串行）', () {
      final rows = buildKitchenLines(ticket(lines: const [
        OrderLine(name: '牛肉炒饭', quantity: 1, unitPrice: 28),
        OrderLine(name: '可乐', quantity: 2, unitPrice: 10),
      ]));
      final a = rows.indexWhere((r) => r.contains('牛肉炒饭'));
      final b = rows.indexWhere((r) => r.contains('可乐'));
      expect(b, greaterThan(a));
      expect(rows.sublist(a + 1, b).any((r) => r.trim().isEmpty), isTrue,
          reason: '两道菜之间应该空一行：\n${rows.join('\n')}');
    });

    test('⑨ 菜名独占一行；定制项/备注从下一行、从菜名列开始', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          options: ['加辣'],
          notes: ['不要香菜', '少放盐'],
        ),
      ]));
      final itemCols = kitchenItemColumns('58');

      // ① 菜品行 = 数量 + 菜名，菜名独占这一行
      final item = rows.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains('牛肉炒饭'));
      expect(item.bold, isTrue, reason: '数量和菜名要加粗');
      expect(item.continueLine, isFalse, reason: '不再跟备注并排');
      expect(displayWidth(item.text), itemCols);
      expect(item.text.trimLeft().startsWith('1'), isTrue,
          reason: '数量贴最左：${item.text}');

      // ② 定制项 / 备注从下一行开始，从第 6 格（普通字号第 11 列）开始；
      //    58mm 让出数量列后一行放不下三条，会按 ` / ` 分两行，每行都从菜名列开始。
      final i = rows.indexOf(item);
      final noteLine = rows[i + 1];
      expect(noteLine.text.trim(), '加辣 / 不要香菜');
      expect(noteLine.scale, TicketScale.large, reason: '备注是「大」');
      expect(noteLine.bold, isFalse, reason: '备注不加粗');
      expect(noteLine.continueLine, isFalse);
      expect(displayWidth(noteLine.text), 32, reason: '整行铺满');
      expect(noteLine.text,
          padRight('${' ' * 10}加辣 / 不要香菜', 32),
          reason: '备注要和菜名从同一列开始：${noteLine.text}');
      final noteLine2 = rows[i + 2];
      expect(noteLine2.text.trim(), '少放盐');
      expect(noteLine2.text, padRight('${' ' * 10}少放盐', 32));
    });

    test('⑨a **只有特别备注、没有定制项**：同样从下一行、从菜名那一列开始', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          notes: ['不要香菜', '少辣'], // 没有 options
        ),
      ]));

      final item = rows.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains('牛肉炒饭'));
      expect(item.continueLine, isFalse);
      final i = rows.indexOf(item);
      final noteLine = rows[i + 1];
      expect(noteLine.text.trim(), '不要香菜 / 少辣');
      expect(noteLine.scale, TicketScale.large);
      expect(noteLine.text,
          padRight('${' ' * 10}不要香菜 / 少辣', 32));
    });

    test('⑨a2 长定制项不抢菜名位置：菜名一行，定制项下一行从菜名列开始', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          options: ['Sin cebolla'], // 11 列，以前会挤到菜名右边
          notes: ['少辣'],
        ),
      ]));

      final item = rows.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains('牛肉炒饭'));
      expect(item.bold, isTrue);
      expect(item.continueLine, isFalse);
      expect(displayWidth(item.text), kitchenItemColumns('58'),
          reason: '菜名不再让地方给右边备注');
      expect(item.text, contains('牛肉炒饭'));

      final i = rows.indexOf(item);
      final noteLine = rows[i + 1];
      expect(noteLine.text.trim(), 'Sin cebolla / 少辣');
      expect(noteLine.scale, TicketScale.large);
      expect(noteLine.text,
          padRight('${' ' * 10}Sin cebolla / 少辣', 32));
    });

    test('⑨a3 **80mm 纸**：菜名占满 24 列，备注下一行从菜名列开始', () {
      final rows = buildKitchenRows(ticket(
        paperWidth: '80',
        lines: const [
          OrderLine(
            name: '牛肉炒饭',
            quantity: 2,
            unitPrice: 28,
            options: ['加辣'],
            notes: ['不要香菜'],
          ),
        ],
      ));

      final item = rows.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains('牛肉炒饭'));
      expect(item.continueLine, isFalse);
      expect(displayWidth(item.text), kitchenItemColumns('80'));
      final noteLine = rows[rows.indexOf(item) + 1];
      expect(noteLine.text.trim(), '加辣 / 不要香菜');
      expect(noteLine.scale, TicketScale.large);
      expect(noteLine.text,
          padRight('${' ' * 10}加辣 / 不要香菜', 48));
    });

    test('⑨b 一条备注特别长：按可用宽度**折行**打，每段都从菜名列开始，一个字都不丢', () {
      const long = '不要香菜不要洋葱不要辣椒不要葱花不要蒜末不要柠檬不要冰';
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          notes: [long],
        ),
      ]));

      final item = rows.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains('牛肉炒饭'));
      expect(item.continueLine, isFalse);
      bool isDashText(String s) =>
          s.trim().isNotEmpty && s.trim().runes.every((c) => c == 0x2D || c == 0x20);
      final noteRows = <TicketRow>[];
      for (final r in rows.skip(rows.indexOf(item) + 1)) {
        if (r.text.trim().isEmpty || isDashText(r.text)) break;
        noteRows.add(r);
      }
      expect(noteRows.length, greaterThan(1), reason: '这么长该折成好几行');
      for (final r in noteRows) {
        expect(r.bold, isFalse, reason: '备注不加粗');
        expect(r.scale, TicketScale.large, reason: '备注是「大」');
        expect(displayWidth(r.text), 32, reason: '每一段都铺满');
        expect(r.text, padRight('${' ' * 10}${r.text.trim()}', 32),
            reason: '每段都要从菜名列开始：${r.text}');
      }
      // 折行之后内容一模一样（去掉空白再比）—— 一个字都没丢
      final flat = rows.map((r) => r.text).join().replaceAll(' ', '');
      expect(flat, contains(long));
    });

    test('⑨c 没有选项 / 备注时：菜品行**铺满整行**，不会多出备注尾巴', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
      ]));
      final item = rows.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(displayWidth(item.text), kitchenItemColumns('58'));
      expect(item.continueLine, isFalse);
    });

    test('⑨d 不再有表头行', () {
      final rows = buildKitchenLines(ticket(lines: const [
        OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
      ]));
      expect(rows.any((r) => r.contains('菜名') && r.contains('数量')), isFalse);
    });

    test('⑩ 58 / 80mm 每一行都不超过**自己字号**的列数（长名字 / 长备注也不爆）', () {
      for (final paper in const ['58', '80']) {
        final paperCols = receiptColumns(paper);
        final rows = buildKitchenRows(ticket(
          paperWidth: paper,
          table: '',
          takeaway: true,
          label: '名字特别特别长的外卖客人',
          dailyNo: 3,
          waitMinutes: 120,
          western: 'LLEVAR',
          chinese: '电话外卖',
          lines: const [
            OrderLine(
              name: 'Chop Suey Pollo Grande',
              quantity: 12,
              unitPrice: 160,
              unit: '份',
              options: ['Sin cebolla', 'Sin cilantro'],
              notes: ['不要香菜不要洋葱', 'poner salsa aparte por favor'],
            ),
          ],
        ));
        for (final r in rows) {
          expect(displayWidth(r.text) <= r.scale.columnsFor(paperCols), isTrue,
              reason: '${paper}mm 行超宽: "${r.text}" (${r.scale})');
        }
      }
    });

    test('⑪ 外卖的名字再长也不切字（特大放不下就退「大」，再放不下退普通）', () {
      final rows = buildKitchenRows(ticket(
        table: '',
        takeaway: true,
        label: '名字特别特别长的外卖客人', // 24 列 > 特大 16 列
        chinese: '外卖',
      ));
      final who = rows.firstWhere((r) => r.text.contains('名字特别'));
      expect(who.text.contains('名字特别特别长的外卖客人'), isTrue,
          reason: '一个字都不能切："${who.text}"');
      expect(who.scale, TicketScale.large, reason: '放不下特大就退「大」');
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

    /// **去掉空白、边纹和换行**再比。
    ///
    /// 边纹只可能是 `◆`（cp850 的 `#` 退路只用于打印字节，不会出现在这里的
    /// 默认 gbk 版式测试里；`#` 本身也是昵称 `L #1` 的正常字符，不能删）。
    String flat(String ticket) =>
        ticket.replaceAll(RegExp(r'[\s◆]+'), '');

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

  // ---------------------------------------------------------------------
  // 小票上的定制项 / 特别备注：**一条一行打在菜品下面**（不再塞进括号里）
  // ---------------------------------------------------------------------
  group('小票：定制项 / 特别备注一条一行', () {
    ReceiptData data({double notePrice = 0}) => ReceiptData(
          storeName: '我的餐厅',
          currency: '¥',
          paymentMethodLabel: '现金',
          lines: [
            OrderLine(
              name: '牛肉炒饭',
              quantity: 1,
              unitPrice: 28,
              options: const ['Grande'],
              notes: const ['换炒饭', '不要洋葱'],
              notePrices: [notePrice],
            ),
          ],
          total: 28 + notePrice,
          thankyou: '谢谢光临',
          paperWidth: '58',
          labels: const ReceiptLabels(labelTotal: '合计', labelPay: '支付方式'),
        );

    test('菜名那一行**不再带括号选项**；选项和每条备注各占一行', () {
      final lines = buildReceiptLines(data());
      final nameLine = lines.firstWhere((l) => l.contains('牛肉炒饭'));
      expect(nameLine.contains('('), isFalse, reason: '菜名后面不该再塞括号选项');
      expect(nameLine.contains('Grande'), isFalse);
      expect(nameLine.trimRight(), endsWith('¥28.00'));

      // 顺序：菜名 → 「1 x ¥28.00」→ 选项 → 备注1 → 备注2
      final at = lines.indexOf(nameLine);
      expect(lines[at + 1], contains('x'));
      expect(lines[at + 2].trim(), 'Grande', reason: '选项要单独一行');
      expect(lines[at + 3].trim(), '换炒饭', reason: '备注一条一行');
      expect(lines[at + 4].trim(), '不要洋葱');
    });

    test('备注带加价：那一行写 `换炒饭 +70`，菜名那行金额也跟着变', () {
      final lines = buildReceiptLines(data(notePrice: 70));
      expect(lines.any((l) => l.trim() == '换炒饭 +70'), isTrue,
          reason: '加价要写在备注那一行上：\n${lines.join('\n')}');
      final nameLine = lines.firstWhere((l) => l.contains('牛肉炒饭'));
      expect(nameLine.trimRight(), endsWith('¥98.00'), reason: '28 + 70');
    });
  });

  // ---------------------------------------------------------------------
  // 厨师单「数量」列：按规则表换成老板手写单的习惯（1 / N/2 / ①）
  // ---------------------------------------------------------------------
  group('厨师单数量列：按手写习惯换算（规则表 + 开关）', () {
    /// 一道带 Size 的菜（`size == null` = 没选 / 没有 Size 这一组）。
    OrderLine line({
      required int qty,
      String? size,
      String group = 'Size',
      String unit = '',
      String name = 'Chun Kun',
    }) =>
        OrderLine(
          name: name,
          quantity: qty,
          unitPrice: 120,
          unit: unit,
          options: size == null ? const [] : [size],
          optionGroups: size == null ? const {} : {group: size},
        );

    /// 把一行菜排成厨师单（58mm），返回所有行。
    List<TicketRow> rows(OrderLine l, {String codec = 'gbk'}) => buildKitchenRows(
          KitchenData(
            table: '5',
            orderId: 'o1',
            createdAt: DateTime(2026, 10, 18, 13, 0),
            lines: [l],
            paperWidth: '58',
            codec: codec,
            labels: const KitchenLabels(
              title: '厨师单',
              labelTable: '桌号',
              colName: '菜名',
              colQty: '数量',
              colNote: '备注',
              append: '追加',
            ),
          ),
        );

    /// 「数量 + 菜名」那一行（菜品行本体）。
    TicketRow itemHead(OrderLine l, {String codec = 'gbk'}) =>
        rows(l, codec: codec).firstWhere((r) =>
            r.scale == kKitchenItemScale && r.text.contains(l.displayName));

    test('Grande → 份数（1 份写 1、2 份写 2）', () {
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Grande')), '1');
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: 'Grande')), '2');
    });

    test('Mediano → 份数/2，**不约分**（1→1/2、2→2/2、3→3/2、4→4/2）', () {
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Mediano')), '1/2');
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: 'Mediano')), '2/2',
          reason: '两份 Mediano 就写 2/2，不要约成 1（几份就要看得出几份）');
      expect(kitchenQtyShorthandLabel(line(qty: 3, size: 'Mediano')), '3/2');
      expect(kitchenQtyShorthandLabel(line(qty: 4, size: 'Mediano')), '4/2');
    });

    test('Chico → 圆圈里的份数（① ② ⑩；11 份以上写 (11)）', () {
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Chico')), '①');
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: 'Chico')), '②');
      expect(kitchenQtyShorthandLabel(line(qty: 10, size: 'Chico')), '⑩');
      expect(kitchenQtyShorthandLabel(line(qty: 11, size: 'Chico')), '(11)',
          reason: '⑪ 起 GBK 里没有，会打成问号');
    });

    test('没 Size / 选了别的（VASO、JARRA）/ 老数据没组名 → 不换算', () {
      expect(kitchenQtyShorthandLabel(line(qty: 2)), isNull);
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: 'VASO')), isNull);
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: 'JARRA')), isNull);
      // 老单：options 有 Grande，但没有 optionGroups（升级前存的）
      const old = OrderLine(
        name: 'Chun Kun',
        quantity: 1,
        unitPrice: 120,
        options: ['Grande'],
      );
      expect(kitchenQtyShorthandLabel(old), isNull, reason: '认不出组名就不换算');
    });

    test('组名 / 选项值不分大小写，阴性写法（mediana / chica）也认', () {
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'grande')), '1');
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Mediano', group: 'size')),
          '1/2');
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'mediana')), '1/2');
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Chica')), '①');
    });

    test('cp850 / latin1 打不出 ① → 改成 (1)（不乱码）', () {
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Chico'), codec: 'cp850'),
          '(1)');
      expect(
          kitchenQtyShorthandLabel(line(qty: 2, size: 'Chico'), codec: 'latin1'),
          '(2)');
      // gbk 默认：还是圆圈数字
      expect(kitchenQtyShorthandLabel(line(qty: 1, size: 'Chico')), '①');
    });

    test('真打在小票上：数量列 2/2，定制项 Mediano 从下一行菜名列开始', () {
      final l = line(qty: 2, size: 'Mediano');
      final rs = rows(l);
      final item = rs.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains(l.displayName));
      expect(item.text.startsWith('2/2'), isTrue,
          reason: '数量列应该从 2/2 开始：`${item.text}`');
      expect(item.scale, kKitchenItemScale);
      // 一行都不超宽（58mm = 32 列；每一行按自己的字号换算）
      for (final r in rs) {
        expect(displayWidth(r.text), lessThanOrEqualTo(r.scale.columnsFor(32)),
            reason: '超宽会被打印机自己折行：`${r.text}`');
      }
      // 定制项 Mediano 从下一行开始，从菜名列开始
      final note = rs[rs.indexOf(item) + 1];
      expect(note.text.trim(), 'Mediano');
      expect(note.text, padRight('${' ' * 10}Mediano', 32));
    });

    test('Chico 1 份：数量列打 ①（按 2 列算，整行不会挤歪）', () {
      final l = line(qty: 1, size: 'Chico');
      final rs = rows(l);
      final item = rs.firstWhere((r) =>
          r.scale == kKitchenItemScale && r.text.contains(l.displayName));
      expect(item.text.startsWith('①'), isTrue, reason: '`${item.text}`');
      for (final r in rs) {
        expect(displayWidth(r.text), lessThanOrEqualTo(r.scale.columnsFor(32)),
            reason: '超宽会被打印机自己折行：`${r.text}`');
      }
      final note = rs[rs.indexOf(item) + 1];
      expect(note.text.trim(), 'Chico');
      expect(note.text, padRight('${' ' * 10}Chico', 32));
    });

    test('份数太多放不下（150 份 Mediano = `150/2`，5 列 > 4 列）→ 退回真实份数', () {
      final head = itemHead(line(qty: 150, size: 'Mediano'));
      expect(head.text.startsWith('150'), isTrue,
          reason: '宁可不符合手写习惯，也不能让厨房看错份数：`${head.text}`');
      expect(head.text.contains('150/2'), isFalse);
    });

    test('没有 Size 的菜：数量列还是老样子（份数 / 份数+单位）', () {
      // 普通定制项（辣度，不是 Size）→ 不换算；那一行同样是「数量+菜名」前半段
      expect(
        itemHead(line(qty: 2, size: '中辣', group: '辣度')).text.startsWith('2'),
        isTrue,
      );
      expect(
        itemHead(line(qty: 2, size: '中辣', group: '辣度', unit: '份'))
            .text
            .startsWith('2 份'),
        isTrue,
      );
    });

    // 这块是**外挂**：规则全在 kKitchenQtyRules 这张表里，加一行就多一条规则。
    test('规则表是模块化的：Size 的三档 + 开关都在表 / 常量里', () {
      expect(kKitchenQtyShorthandEnabled, isTrue, reason: '总开关（关掉整块失效）');
      // 三条规则都在表里（要加规则就往表里加一行，函数不用改）
      expect(
          kKitchenQtyRules.any((r) =>
              r.group == 'Size' &&
              r.option == 'Grande' &&
              r.style == KitchenQtyStyle.count),
          isTrue);
      expect(
          kKitchenQtyRules.any((r) =>
              r.group == 'Size' &&
              r.option == 'Mediano' &&
              r.style == KitchenQtyStyle.halves),
          isTrue);
      expect(
          kKitchenQtyRules.any((r) =>
              r.group == 'Size' &&
              r.option == 'Chico' &&
              r.style == KitchenQtyStyle.circled),
          isTrue);
      // 表里没有的组（例如「辣度」）不会被误换算
      expect(kitchenQtyShorthandLabel(line(qty: 2, size: '特辣', group: '辣度')),
          isNull);
    });
  });

  // ---------------------------------------------------------------------
  // 日结：整张按「大号」打（三列：名字左 / 金额中 / 右侧留白手写）
  // ---------------------------------------------------------------------
  group('日结小票：大号三列', () {
    SummaryData data({String paperWidth = '58'}) => SummaryData(
          storeName: '我的餐厅',
          dateLabel: '2026-10-18',
          paperWidth: paperWidth,
          currency: '¥',
          dineInTotal: 84,
          takeawayTotal: 28,
          cashByCurrency: const {'MXN': 28},
          cardTotal: 84,
          qrTotal: 0,
          total: 112,
          expense: 0,
          orderCount: 2,
          labels: const SummaryLabels(
            title: '日结',
            date: '日期',
            dineIn: '堂食',
            takeaway: '外卖',
            cash: '现金',
            card: '刷卡',
            qr: '扫码',
            total: '总营业额',
            expense: '支出',
            net: '净额',
            orders: '单数',
          ),
        );

    test('每行都是大号，而且不超过大号下的列数（58mm = 32 列）', () {
      final lines = TicketBuilder.summaryLines(data());
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l.scale, TicketScale.large, reason: '日结要按大号打：${l.text}');
        expect(displayWidth(l.text), lessThanOrEqualTo(32),
            reason: '超宽会被打印机自己折行：`${l.text}`');
      }
      final text = lines.map((l) => l.text).join('\n');
      expect(text, contains('总营业额'));
      expect(text, contains('112.00'));
      expect(text, contains('日结'));
      // 现金固定两行：MXN / USD（USD 没有收款也显示 0）
      expect(text, contains('现金 MXN'));
      expect(text, contains('现金 USD'));
    });

    test('80mm 同样一行不超宽（大号下 48 列）', () {
      final lines = TicketBuilder.summaryLines(data(paperWidth: '80'));
      for (final l in lines) {
        expect(displayWidth(l.text), lessThanOrEqualTo(48),
            reason: '`${l.text}`');
      }
    });

    test('中文行强制 GBK 中文模式（西语编码下也不会变问号）', () {
      final lines = TicketBuilder.summaryLines(data());
      final title = lines.firstWhere((l) => l.text.contains('日结'));
      expect(title.raw, isNotNull,
          reason: '中文标题要自己进出中文模式，不能交给 cp850/latin1');
      expect(title.raw, contains(0x1C)); // FS
      expect(title.raw, contains(0x26)); // &
      // 纯 ASCII 的分隔线仍走普通编码，不需要切换中文模式
      final divider = lines.firstWhere((l) => l.text.startsWith('='));
      expect(divider.raw, isNull);
    });

    test('打印顺序：分类 → 现金 MXN/USD → 刷卡 → 支出 → 总营业额，明细不空行', () {
      final lines = TicketBuilder.summaryLines(data());
      final texts = lines.map((l) => l.text.trim()).toList();
      int at(String prefix) =>
          texts.indexWhere((t) => t.startsWith(prefix));

      final iDine = at('堂食');
      final iCashMxn = at('现金 MXN');
      final iCashUsd = at('现金 USD');
      final iCard = at('刷卡');
      final iExpense = at('支出');
      final iTotal = at('总营业额');
      expect(iDine, greaterThanOrEqualTo(0));
      expect(iCashMxn, greaterThanOrEqualTo(0));
      expect(iCashUsd, greaterThanOrEqualTo(0));
      expect(iDine, lessThan(iCashMxn));
      expect(iCashMxn, lessThan(iCashUsd));
      expect(iCashUsd, lessThan(iCard));
      expect(iCard, lessThan(iExpense));
      expect(iExpense, lessThan(iTotal));

      // 每条明细一行；不再插入空行
      expect(texts.where((t) => t.isEmpty), isEmpty);
      expect(texts[iDine + 1], isNotEmpty);
      expect(texts[iCashMxn + 1], isNotEmpty);
      expect(texts[iExpense + 1], isNotEmpty);
    });

    // 平台外卖（Uber / DiDi 这种）：**左侧单独一行**；
    // **右侧**平台收的刷卡单列「平台刷卡」（现金已经并进「现金」）。
    test('平台外卖：左侧单独一行、右侧「平台刷卡」单列（刷卡里不含它）', () {
      final lines = TicketBuilder.summaryLines(SummaryData(
        storeName: '我的餐厅',
        dateLabel: '2026-10-18',
        paperWidth: '58',
        currency: '¥',
        dineInTotal: 28,
        takeawayTotal: 5,
        phoneTakeawayTotal: 8,
        platformTakeawayTotal: 40,
        cashByCurrency: const {'MXN': 36},
        cardTotal: 5, // 普通刷卡（不含平台）
        platformCardTotal: 32, // 平台外卖刷的卡
        qrTotal: 0,
        total: 81, // 28 + 5 + 8 + 40
        expense: 0,
        orderCount: 4,
        labels: const SummaryLabels(
          title: '日结',
          date: '日期',
          dineIn: '堂食',
          takeaway: '外卖',
          phoneTakeaway: '电话外卖',
          platformTakeaway: '平台外卖',
          platformCard: '平台刷卡',
          cash: '现金',
          card: '刷卡',
          qr: '扫码',
          total: '总营业额',
          expense: '支出',
          net: '净额',
          orders: '单数',
        ),
      ));
      final text = lines.map((l) => l.text).join('\n');
      expect(text, contains('平台外卖'));
      expect(text, contains('平台刷卡'));
      expect(text, contains('40.00'), reason: '平台外卖的营业额');
      expect(text, contains('32.00'), reason: '平台刷卡的钱');
      // 平台刷卡**不再**混进普通「刷卡」那一行（只有 5.00）
      final cardRow = lines.firstWhere((l) => l.text.trimLeft().startsWith('刷卡'));
      expect(cardRow.text, contains('5.00'));
      expect(cardRow.text, isNot(contains('37.00')));
      // 一行都不超宽（58mm 大号 = 32 列）
      for (final l in lines) {
        expect(displayWidth(l.text), lessThanOrEqualTo(32),
            reason: '超宽会被打印机自己折行：`${l.text}`');
      }
    });
  });

  // 结账窗口里点「打印单子」时，纸上要能对账：**合计下面是实收、再下面是找零**。
  // （窗口那边把实收/找零临时贴到订单副本上再打，见 `payment_flow.dart` 的 `_billToPrint`）
  group('打印「单子」：合计 → 实收 → 找零', () {
    Settings settings() => Settings(storeName: '我的餐厅', paperWidth: '58');

    Order bill({double? received, double? change, PaymentMethod? method}) => Order(
          id: 'o1',
          createdAt: DateTime(2026, 10, 18, 13, 45),
          lines: const [OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28)],
          total: 56,
          paymentMethod: method,
          currencyCode: 'MXN',
          exchangeRate: 0, // 本位币：不换算
          receivedAmount: received,
          changeAmount: change,
        );

    test('现金：合计下面依次是「支付方式 → 实收 → 找零」，金额对', () {
      final lines = TicketBuilder.receiptLines(
        bill(received: 100, change: 44, method: PaymentMethod.cash),
        settings(),
      ).map((l) => l.text).toList();

      final at = lines.indexWhere((l) => l.trimLeft().startsWith('合计'));
      expect(at, greaterThan(0), reason: '纸上必须有一条「合计」：\n${lines.join('\n')}');
      final tail = lines.sublist(at);

      final pay = tail.indexWhere((l) => l.contains('支付'));
      final received = tail.indexWhere((l) => l.contains('实收'));
      final change = tail.indexWhere((l) => l.contains('找零'));
      expect(received, greaterThan(pay), reason: '实收在支付方式下面：\n${tail.join('\n')}');
      expect(change, greaterThan(received), reason: '找零在实收下面：\n${tail.join('\n')}');
      expect(tail[received], contains('100.00'));
      expect(tail[change], contains('44.00'));
    });

    test('没填实收（还没收钱 / 刷卡）→ 纸上没有实收、找零这两行', () {
      final lines = TicketBuilder.receiptLines(
        bill(method: PaymentMethod.card),
        settings(),
      ).map((l) => l.text);
      expect(lines.any((l) => l.contains('实收')), isFalse);
      expect(lines.any((l) => l.contains('找零')), isFalse);
    });
  });
}
