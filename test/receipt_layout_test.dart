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

  group('厨师单菜品列：**数量 | 菜名（居中）| 备注**', () {
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

    test('表头是「数量 菜名 备注」，数量在最左、备注在最右', () {
      final l = lines();
      final header = l.firstWhere((x) => x.contains('菜名'));
      expect(header.trimLeft().startsWith('数量'), isTrue,
          reason: '表头应该是「数量 菜名 备注」：$header');
      expect(header.indexOf('数量') < header.indexOf('菜名'), isTrue,
          reason: '数量必须排在菜名左边：$header');
      expect(header.indexOf('菜名') < header.indexOf('备注'), isTrue,
          reason: '备注必须在菜名右边：$header');
      expect(header.trimRight().endsWith('备注'), isTrue,
          reason: '备注居右（贴着右边缘）：$header');

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

    test('菜名在中间那一列**居中**（中心列对齐，不再挤在数量旁边）', () {
      final l = lines();
      final a = l.firstWhere((x) => x.contains('牛肉炒饭'));
      final b = l.firstWhere((x) => x.contains('可乐'));
      // 注意：要比的是**显示列数**（中文算 2 列），字符串下标在中文行上不等价
      double centerOf(String row, String name) =>
          displayWidth(row.substring(0, row.indexOf(name))) +
          displayWidth(name) / 2;
      expect((centerOf(a, '牛肉炒饭') - centerOf(b, '可乐')).abs() <= 1, isTrue,
          reason: '菜名居中的话，两行菜名的中心应该对齐：\n"$a"\n"$b"');
      // 短名字最能看出居中：`可乐` 前面应该有留白（不是紧贴着数量列）
      final padBefore = displayWidth(b.substring(0, b.indexOf('可乐')));
      expect(padBefore, greaterThan(kKitchenQtyColumns),
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
    bool isDashRow(TicketRow r) =>
        r.scale == TicketScale.normal &&
        r.text.trim().isNotEmpty &&
        r.text.runes.every((c) => c == 0x2D || c == 0x20); // 只有 '-' 和空格

    List<TicketRow> badgeOf(KitchenData k) {
      final rows = buildKitchenRows(k);
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

    test('② 门牌**紧跟时间**（中间不空行）；堂食门牌 = 桌号（特大、居中）', () {
      final rows = buildKitchenRows(ticket());
      final time = rows.indexWhere((r) => r.text.contains('13:45'));
      // 票面上半截要短：时间下面直接就是门牌，不空行
      final who = rows[time + 1];
      expect(who.text.trim(), '桌号 8',
          reason: '时间下面应该紧接着就是门牌：\n${rows.map((r) => r.text).join('\n')}');
      expect(who.scale, kKitchenWhoScale);
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

    test('⑤ 底部徽标：空行 → **西文** → **中文**，两行都是最大字号（没有图案了）', () {
      final badge = badgeOf(ticket());
      expect(badge.first.text.trim(), isEmpty, reason: '徽标前面空一行');
      // 只有两行字：第一行西文、第二行中文（ASCII 图案已经去掉了）
      expect(badge.length, 3, reason: '徽标 = 空行 + 西文 + 中文：\n${badge.map((r) => r.text).join('\n')}');
      final western = badge[1];
      expect(western.text.trim(), 'AQUI');
      expect(western.scale, kKitchenBadgeScale, reason: '西文那行要最大');
      final chinese = badge[2];
      expect(chinese.text.trim(), '堂食');
      expect(chinese.scale, kKitchenBadgeScale, reason: '中文那行要最大');
      // 徽标是票面**最后**的内容（切纸前那一块，插在杆上正好露出来）
      expect(badge.last.text.trim(), '堂食');
    });

    test('⑥ 徽标里**没有** ASCII 图案了（厨师不看图案，那几行纸全省下来）', () {
      for (final takeaway in [false, true]) {
        final badge = badgeOf(ticket(
          table: takeaway ? '' : '8',
          takeaway: takeaway,
          western: takeaway ? 'LLEVAR' : 'AQUI',
          chinese: takeaway ? '外卖' : '堂食',
        ));
        // 空行之后只剩两行字，而且都是纯文字（没有 `|` `_` `/` 这些图案字符）
        expect(badge.length, 3);
        for (final r in badge.skip(1)) {
          expect(RegExp(r'[<>|_/\\]').hasMatch(r.text), isFalse,
              reason: '徽标里不该再有图案字符："${r.text}"');
        }
      }
      // 外卖的徽标是西文 `LLEVAR` + 中文 `外卖`
      final takeaway = badgeOf(ticket(
          table: '', takeaway: true, western: 'LLEVAR', chinese: '外卖'));
      expect(takeaway[1].text.trim(), 'LLEVAR');
      expect(takeaway[2].text.trim(), '外卖');
    });

    test('⑦ 中文那行**强制中文模式**打（整张票设 cp850 也不会变成 `?`）', () {
      final badge = badgeOf(ticket());
      final chinese = badge[2];
      expect(chinese.text.trim(), '堂食');
      // 关键：中文行是**原始字节行**（自带 FS & … FS .），不看当前编码设置
      expect(chinese.raw, isNotNull,
          reason: '中文徽标要走 gbkLineBytes（自己进出中文模式），否则 cp850 下会变 `?`');
      final raw = chinese.raw!.toList();
      expect(_indexOfSeq(raw, const [0x1C, 0x26]), greaterThanOrEqualTo(0),
          reason: '缺 FS &（进中文模式）');
      expect(_indexOfSeq(raw, const [0x1C, 0x2E]), greaterThanOrEqualTo(0),
          reason: '缺 FS .（退出中文模式）');

      // 传空 = 这一行不打（只留西文）
      final none = badgeOf(ticket(chinese: ''));
      expect(none.any((r) => r.text.contains('堂食')), isFalse);
      expect(none.any((r) => r.text.contains('AQUI')), isTrue,
          reason: '西文那行照打');
    });

    test('⑦b 底部徽标：**加粗** + 比菜品再高一档（huge = 2 倍宽 / 3 倍高）', () {
      final badge = badgeOf(ticket());
      final western = badge[1];
      final chinese = badge[2];

      expect(western.scale, TicketScale.huge, reason: '西文那行用最高一档字号');
      expect(chinese.scale, TicketScale.huge);
      expect(kKitchenBadgeScale, TicketScale.huge,
          reason: '这个常量就是徽标的字号，改它就能整体升降档');
      // GS ! 的参数：宽 2 倍（高位 1）、高 3 倍（低位 2）→ 0x12
      expect(TicketScale.huge.gsBangParam, 0x12);

      expect(western.bold, isTrue, reason: '西文行要加粗');
      expect(chinese.bold, isTrue, reason: '中文行要加粗');
      // 中文行走原始字节 → 加粗的 ESC E 1 / ESC E 0 要编进 raw 里
      final raw = chinese.raw!.toList();
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

    test('⑨ **第一条**备注跟菜名同一行（大、不加粗）；剩下的**一条一行**从最左边', () {
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
      final qtyW = kKitchenQtyColumns;
      final noteWXl = itemCols ~/ kKitchenNoteColumnsDivisor;
      final nameW = itemCols - qtyW - noteWXl;

      // ① 第一行 = 「数量 + 菜名」：**特大加粗**、**不换行**（`continueLine`）
      final head = rows.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(head.scale, kKitchenItemScale);
      expect(head.bold, isTrue, reason: '数量和菜名要加粗');
      expect(head.continueLine, isTrue, reason: '第一条备注要紧跟着打在同一行上');
      expect(displayWidth(head.text), qtyW + nameW,
          reason: '正好是"数量列 + 菜名列"，剩下的地方留给备注');

      // ② 同一行接着打第一条备注（**大**、不加粗、**贴右边缘**）
      final note1 = rows[rows.indexOf(head) + 1];
      expect(note1.text.trim(), '加辣');
      expect(note1.scale, TicketScale.large, reason: '备注是「大」，不是「特大」');
      expect(note1.bold, isFalse, reason: '**备注不加粗**');
      expect(note1.continueLine, isFalse, reason: '这段打完要换行');
      // 居右：数量+菜名（特大，算双倍列宽）+ 这一条 = 正好一张纸宽
      expect(displayWidth(head.text) * 2 + displayWidth(note1.text), 32,
          reason: '第一条要顶到纸的右边缘（不然跟菜名挤在中间）：\n'
              '"${head.text}" + "${note1.text}"');

      // ③ 剩下的备注：**一条一行、从最左边**（大、不加粗）
      final note2 = rows[rows.indexOf(note1) + 1];
      expect(note2.text, '不要香菜');
      expect(note2.text.startsWith(' '), isFalse, reason: '从最左边开始打');
      expect(note2.scale, TicketScale.large);
      expect(note2.bold, isFalse);
      final note3 = rows[rows.indexOf(note2) + 1];
      expect(note3.text, '少放盐', reason: '第三条也要单独一行');
    });

    test('⑨a **只有特别备注、没有定制项**：第一条同样在菜品这一行、**贴右边缘**', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          notes: ['不要香菜', '少辣'], // 没有 options
        ),
      ]));

      final head = rows.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(head.continueLine, isTrue,
          reason: '没有定制项时，第一条特别备注也要留在菜品这一行');
      final first = rows[rows.indexOf(head) + 1];
      expect(first.text.trim(), '不要香菜');
      expect(first.scale, TicketScale.large);
      expect(displayWidth(head.text) * 2 + displayWidth(first.text), 32,
          reason: '第一条备注要贴右边缘');

      // 第二条回到最左边、单独一行
      final second = rows[rows.indexOf(first) + 1];
      expect(second.text, '少辣');
      expect(second.text.startsWith(' '), isFalse);
    });

    test('⑨a2 第一个太长：**借菜名的地方**也要留在同一行（还是贴右边缘）', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          options: ['Sin cebolla'], // 11 列 > 默认 8 列的备注列，但没到上限
          notes: ['少辣'],
        ),
      ]));

      // 菜名列被借窄了（8 → 6 个特大列），所以「牛肉炒饭」会折成两行 ——
      // 用 `continueLine` 认这一行（菜品行的前半段就是它）
      final head = rows.firstWhere((r) => r.continueLine);
      expect(head.text.trimLeft().startsWith('1'), isTrue, reason: '数量贴最左');
      final first = rows[rows.indexOf(head) + 1];
      expect(first.text.trim(), 'Sin cebolla', reason: '西文单词不能被劈开');
      expect(displayWidth(head.text) * 2 + displayWidth(first.text), 32,
          reason: '借完地方之后仍然正好顶到右边缘：\n"${head.text}" + "${first.text}"');
      // 菜名那一列被压窄了（< 默认），所以「数量+菜名」比默认短
      final defaultNameW = kitchenItemColumns('58') -
          kKitchenQtyColumns -
          kitchenItemColumns('58') ~/ kKitchenNoteColumnsDivisor;
      expect(displayWidth(head.text), lessThan(kKitchenQtyColumns + defaultNameW));
      // 菜名折行了，但**一个字都没丢** —— 只看这道菜里**特大字号**的那几行
      // （「数量 + 菜名」+ 菜名的折行续行；从 head 往后数，别把前面的门牌/备注混进来）
      final nameRows = rows
          .skip(rows.indexOf(head))
          .where((r) => r.scale == kKitchenItemScale)
          .map((r) => r.text)
          .join()
          .replaceAll(' ', '');
      expect(nameRows, contains('牛肉炒饭'),
          reason: '菜名折成两行也不能丢字：$nameRows');
      // 剩下的备注回到最左边、单独一行（它前面可能还有菜名的折行续行，所以按内容找）
      final restNote = rows
          .skip(rows.indexOf(first))
          .firstWhere((r) => r.text.trim() == '少辣');
      expect(restNote.text, '少辣', reason: '剩下那条备注要从最左边开始打');
      expect(restNote.text.startsWith(' '), isFalse);
    });

    test('⑨a3 **80mm 纸**：数量贴左、第一个贴右（一行 48 列），菜名列更宽', () {
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

      final head = rows.firstWhere((r) => r.continueLine);
      final first = rows[rows.indexOf(head) + 1];
      expect(first.text.trim(), '加辣');
      // 80mm：一行 48 列；「数量+菜名」（特大，双倍宽）+ 这一条 = 48
      expect(displayWidth(head.text) * 2 + displayWidth(first.text), 48,
          reason: '80mm 上第一个也要贴右边缘：\n"${head.text}" + "${first.text}"');
      // 80mm 默认菜名列 = 24 − 4 − (24 ÷ 4 = 6) = 14 个特大列
      expect(displayWidth(head.text), kKitchenQtyColumns + 14,
          reason: '80mm 的菜名列比 58mm（8 列）宽得多');
    });

    test('⑨b 一条备注特别长：按整张纸宽**折行**打，一个字都不丢', () {
      const long = '不要香菜不要洋葱不要辣椒不要葱花不要蒜末不要柠檬不要冰';
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 1,
          unitPrice: 28,
          notes: [long],
        ),
      ]));
      final itemCols = kitchenItemColumns('58');

      // 第一条太长了（> 8 列的备注列）→ 整条挪到下面的行里，按 32 列折
      final item = rows.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(item.continueLine, isFalse,
          reason: '第一条太长了，就别硬塞在这行尾巴上');
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
        expect(displayWidth(r.text) <= 32, isTrue, reason: '备注行超宽: ${r.text}');
      }
      // 折行之后内容一模一样（去掉空白再比）—— 一个字都没丢
      final flat = rows.map((r) => r.text).join().replaceAll(' ', '');
      expect(flat, contains(long));
      expect(itemCols, 16);
    });

    test('⑨c 没有选项 / 备注时：菜品行**铺满整行**，不会多出备注尾巴', () {
      final rows = buildKitchenRows(ticket(lines: const [
        OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
      ]));
      final item = rows.firstWhere((r) => r.text.contains('牛肉炒饭'));
      expect(displayWidth(item.text), kitchenItemColumns('58'));
      expect(item.continueLine, isFalse);
    });

    test('⑨d 表头多了一列「备注」', () {
      final rows = buildKitchenLines(ticket(lines: const [
        OrderLine(name: '牛肉炒饭', quantity: 2, unitPrice: 28),
      ]));
      final header = rows.firstWhere((r) => r.contains('菜名'));
      expect(header, contains('数量'));
      expect(header, contains('备注'));
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
  // 日结：整张按「特大」打（跟厨师单的菜品一样大）
  // ---------------------------------------------------------------------
  group('日结小票：整张「特大」', () {
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

    test('每行都是特大，而且不超过特大下的列数（58mm = 16 列）', () {
      final lines = TicketBuilder.summaryLines(data());
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l.scale, TicketScale.xlarge, reason: '日结要按特大打：${l.text}');
        expect(displayWidth(l.text), lessThanOrEqualTo(16),
            reason: '超宽会被打印机自己折行：`${l.text}`');
      }
      final text = lines.map((l) => l.text).join('\n');
      expect(text, contains('总营业额'));
      expect(text, contains('112.00'));
      expect(text, contains('日结'));
    });

    test('80mm 同样一行不超宽（特大下 24 列）', () {
      final lines = TicketBuilder.summaryLines(data(paperWidth: '80'));
      for (final l in lines) {
        expect(displayWidth(l.text), lessThanOrEqualTo(24),
            reason: '`${l.text}`');
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
