/// **在终端里预演厨师单的版式**（不用真打纸）。
///
/// 用法（在项目根目录）：
/// ```text
/// dart run tool/preview_kitchen.dart          # 58mm
/// dart run tool/preview_kitchen.dart 80       # 80mm
/// ```
///
/// 终端只有一种字号，所以**看不出"大 / 特大"的实际大小** —— 但**行的顺序、
/// 每行多少列、谁在谁上面**跟纸上是一模一样的（每行前面标了它自己的字号）。
/// 改版式（`lib/services/receipt_layout.dart` 的 `buildKitchenRows`）时，
/// 用它先看一眼顺序对不对，再去打纸，能省不少纸。
///
/// ⚠️ 只 import **不依赖 Flutter** 的文件（`receipt_layout` / `models`），
/// 所以可以直接 `dart run`；`ticket_builder`（要用 l10n）不能在这里用，
/// 下面手写 KitchenData 当例子。
library;

import 'dart:io';

import 'package:big_boss_bro/models/order.dart';
import 'package:big_boss_bro/services/escpos.dart';
import 'package:big_boss_bro/services/receipt_layout.dart';

const _labels = KitchenLabels(
  title: '厨师单',
  labelTable: '桌号',
  colName: '菜名',
  colQty: '数量',
  colNote: '备注',
  append: '（追加）',
  wait: '等待',
  minutes: '分钟',
);

void main(List<String> args) {
  final paper = args.isNotEmpty && args.first == '80' ? '80' : '58';
  final cols = receiptColumns(paper);
  final at = DateTime(2026, 10, 11, 13, 45);

  final cases = <String, KitchenData>{
    '堂食（桌号 8）': KitchenData(
      table: '8',
      orderId: '20261011-001',
      createdAt: at,
      paperWidth: paper,
      copyIndex: 1,
      copyTotal: 2,
      typeLabel: '堂食',
      badgeWestern: 'AQUI',
      badgeChinese: '堂食',
      labels: _labels,
      lines: const [
        OrderLine(
          name: '牛肉炒饭',
          quantity: 2,
          unitPrice: 28,
          unit: '份',
          options: ['加辣'],
          notes: ['不要香菜'],
        ),
        OrderLine(name: '可乐', quantity: 1, unitPrice: 5),
      ],
    ),
    '外卖（有名字）': KitchenData(
      table: '',
      orderId: '20261011-002',
      createdAt: at,
      paperWidth: paper,
      copyIndex: 2,
      copyTotal: 2,
      isTakeaway: true,
      orderLabel: '张三',
      typeLabel: '外卖',
      badgeWestern: 'LLEVAR',
      badgeChinese: '外卖',
      labels: _labels,
      lines: const [
        OrderLine(name: 'Chop Suey Pollo', quantity: 1, unitPrice: 160),
      ],
    ),
    '外卖（没名字 → 打系统给的号）+ 电话外卖的等待时间': KitchenData(
      table: '',
      orderId: '20261011-003',
      createdAt: at,
      paperWidth: paper,
      isTakeaway: true,
      dailyNo: 3,
      waitMinutes: 20,
      typeLabel: '电话外卖',
      badgeWestern: 'TELEFONO',
      badgeChinese: '电话外卖',
      labels: _labels,
      lines: const [
        OrderLine(
          name: 'Lonche14',
          quantity: 3,
          unitPrice: 65,
          options: ['Grande'],
          notes: ['不要香菜不要洋葱不要辣椒不要葱花'],
        ),
      ],
    ),
  };

  out('');
  out('厨师单版式预览  ·  $paper mm（普通字号一行 $cols 列）');
  out('终端看不出字号大小，只验证**顺序 / 列宽**；[  ] 里是那一行的字号。');
  out('');
  cases.forEach((name, data) {
    out('─' * (cols + 8));
    out('▶ $name');
    out('─' * (cols + 8));
    out('       ${_ruler(cols)}');
    for (final row in buildKitchenRows(data)) {
      final w = displayWidth(row.text);
      final flag = w > row.scale.columnsFor(cols) ? ' ⚠超宽' : '';
      out('[${_tag(row.scale)}] ${row.text}$flag');
    }
    out('');
  });
  out('（真打出来的样子：请点 App 里的「厨房」打一张；');
  out('  行距旋钮在 escpos.dart 的 kKitchenExtraFeedDots，字号旋钮在 receipt_layout.dart）');
}

/// 输出一行（用 `stdout` 而不是 `print`：`avoid_print` 那条 lint 会报警告）。
void out(String s) => stdout.writeln(s);

/// 每一行前面的字号标签（都是 4 列宽，跟尺子对齐）。
///
/// ⚠️ 必须把 [TicketScale] 的**每一档**都列出来（switch 要穷尽），
/// 否则 `flutter analyze` 会报 non_exhaustive_switch_statement ——
/// 以后再加字号档位，这里也要跟着补一个 case。
String _tag(TicketScale s) {
  switch (s) {
    case TicketScale.normal:
      return '普通';
    case TicketScale.large:
      return '大  ';
    case TicketScale.xlarge:
      return '特大';
    // 厨师单底部徽标用的「超高」（双倍宽 + 三倍高）：
    // 终端里只标个名字，真打出来见 kKitchenBadgeScale
    case TicketScale.huge:
      return '超高';
  }
}

/// 列数尺子：每 5 列一个 `.`/`+`，每 10 列标一下位数。
String _ruler(int cols) {
  final b = StringBuffer();
  for (var i = 1; i <= cols; i++) {
    if (i % 10 == 0) {
      b.write((i ~/ 10) % 10);
    } else if (i % 5 == 0) {
      b.write('+');
    } else {
      b.write('.');
    }
  }
  return b.toString();
}
